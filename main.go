package main

import (
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/spf13/viper"
)

var mainThreadName = "main"
var quit = make(chan bool)
var stopLoop = make(chan bool)

func main() {
	if path.Base(os.Args[0]) == "service" {
		mainService()
	} else {
		mainWatcher()
	}
}

func mainService() {
	if err := os.Setenv("TESTS_MODE", "1"); err != nil {
		log.Fatalf("[%s] cannot set environment variable: %s", mainThreadName, err)
	}
	if len(os.Args) != 3 || (os.Args[2] != "start" && os.Args[2] != "stop") {
		log.Fatalln("usage: service application [start|stop]")
	}
	readConfig()

	if os.Args[2] == "start" {
		addService(os.Args[1])
		start(os.Args[1])
	} else if os.Args[2] == "stop" {
		stop(os.Args[1])
		removeService(os.Args[1])
	}
}

func addService(service string) {
	servicePath := viper.GetString(mainThreadName+".initrd_path") + "/" + strings.TrimSpace(service)
	if _, err := os.Stat(servicePath); os.IsNotExist(err) {
		log.Fatalf("[%s] cannot find service: %s", mainThreadName, err)
	}
	viper.Set(service+".pid_file", viper.GetString(mainThreadName+".pid_path")+"/"+service+".pid")
	viper.Set(service+".start_command", servicePath+" start")
	viper.Set(service+".stop_command", servicePath+" stop")
	if err := viper.WriteConfig(); err != nil {
		log.Fatalf("[%s] cannot save config: %s", mainThreadName, err)
	}
}

func removeService(service string) {
	viperNew := viper.New()
	viperNew.SetConfigFile(viper.ConfigFileUsed())
	log.Println(viper.ConfigFileUsed())
	for _, key := range viper.AllKeys() {
		if strings.HasPrefix(key, service+".") {
			//log.Println("[%s] remove %s service", mainThreadName, service)
		} else {
			viperNew.Set(key, viper.Get(key))
		}
	}
	if err := viperNew.WriteConfig(); err != nil {
		log.Fatalf("[%s] cannot save config: %s", mainThreadName, err)
	}
}

func mainWatcher() {
	readConfig()
	checkOnceRun()
	setSignal()

	go func() {
		for {
			time.Sleep(viper.GetDuration(mainThreadName + ".interval"))
			stopLoop <- false
		}
	}()

	for {
		for service := range viper.AllSettings() {
			if service != mainThreadName {
				if status := isRunning(service); status {
					log.Printf("[%s] running", service)
				} else {
					start(service)
				}
			}
		}
		log.Println()

		if <-stopLoop {
			break
		}
	}
	<-quit
}

func readConfig() {
	if testsMode, err := strconv.ParseBool(os.Getenv("TESTS_MODE")); testsMode && err == nil {
		log.SetFlags(log.Flags() &^ (log.Ldate | log.Ltime))
	}

	log.Printf("[%s] configuration:", mainThreadName)
	viper.AddConfigPath(".")
	if argConfig := os.Getenv("PID_WATCHER_CONFIG"); len(argConfig) > 0 {
		viper.SetConfigFile(argConfig)
		log.Printf("  config = %s", argConfig)
	}

	if err := viper.ReadInConfig(); err != nil {
		log.Println(err)
		os.Exit(1)
	}

	viper.SetDefault(mainThreadName+".pid_path", "/var/run")
	viper.SetDefault(mainThreadName+".initrd_path", "/etc/init.d")
	viper.SetDefault(mainThreadName+".interval", "15s")
	viper.SetDefault(mainThreadName+".kill_interval", "4s")
	viper.SetDefault(mainThreadName+".pid_file", "pid-watchdog.pid")
	for service := range viper.AllSettings() {
		if service != mainThreadName {
			viper.SetDefault(service+".pid_file", viper.GetString(mainThreadName+".pid_file")+"/"+service+".pid")
			viper.SetDefault(service+".start_command", viper.GetString(mainThreadName+".initrd_path")+"/"+service+" start")
			viper.SetDefault(service+".stop_command", viper.GetString(mainThreadName+".initrd_path")+"/"+service+" stop")
		}
	}

	if testsMode, err := strconv.ParseBool(os.Getenv("TESTS_MODE")); !testsMode || err != nil {
		keys := viper.AllKeys()
		sort.Strings(keys)
		for _, key := range keys {
			log.Printf("  %s = %s\n", key, viper.GetString(key))
		}
	}
	log.Println()
	viper.WatchConfig()
}

func checkOnceRun() {
	if status := isRunning(mainThreadName); status {
		log.Printf("[%s] app already is running, exiting", mainThreadName)
		os.Exit(0)
	}
	writePid()
}

func setSignal() {
	sigStop := make(chan os.Signal, 1)
	signal.Notify(
		sigStop,
		syscall.SIGINT,
		syscall.SIGTERM,
		syscall.SIGQUIT,
	)
	go func() {
		<-sigStop
		stopLoop <- true
		log.Printf("[%s] stopping", mainThreadName)

		// stop services
		for service := range viper.AllSettings() {
			if service != mainThreadName {
				stop(service)
			}
		}

		// remove pid
		pidPath := viper.GetString(mainThreadName + ".pid_file")
		os.Remove(pidPath) // nolint: errcheck, gosec

		quit <- true
	}()
}

func isRunning(service string) bool {
	pidPath := viper.GetString(service + ".pid_file")
	if _, err := os.Stat(pidPath); os.IsNotExist(err) {
		return false
	}

	pid, err := getPid(pidPath)
	if err != nil {
		log.Printf("[%s] error parsing pid: %s", service, err)
		return false
	}

	if status := isRunningPid(pid); status {
		return true
	}

	return false
}

func start(service string) {
	startCmd := viper.GetString(service + ".start_command")
	startProcess := exec.Command("sh", "-c", startCmd) // nolint: gosec
	startProcess.Stdout = os.Stdout
	if err := startProcess.Start(); err != nil {
		log.Printf("[%s] error starting service: %s", service, err)
		return
	}
	log.Printf("[%s] starting", service)
}

func stop(service string) {
	log.Printf("[%s] stopping", service)
	stopCmd := viper.GetString(service + ".stop_command")
	stopProcess := exec.Command("sh", "-c", stopCmd) // nolint: gosec
	stopProcess.Stdout = os.Stdout
	if err := stopProcess.Start(); err != nil {
		log.Printf("[%s] error stopping service: %s", service, err)
		return
	}
	killInteval := int(viper.GetDuration(mainThreadName+".kill_interval") / time.Second)
	for i := 0; i < 4*killInteval; i++ {
		//log.Println("kill loop:", i, isRunning(service))
		if !isRunning(service) {
			return
		}
		time.Sleep(250 * time.Millisecond)
	}
	kill(service)
}

func kill(service string) {
	pidPath := viper.GetString(service + ".pid_file")
	if _, err := os.Stat(pidPath); os.IsNotExist(err) {
		return
	}

	pid, err := getPid(pidPath)
	if err != nil {
		return
	}

	process, err := os.FindProcess(pid)
	if err != nil {
		return
	}

	log.Printf("[%s] force kill", service)
	process.Signal(syscall.Signal(9)) // nolint: errcheck, gosec
}

func getPid(filename string) (int, error) {
	contents, err := ioutil.ReadFile(filename) // nolint: gosec
	if err != nil {
		return 0, err
	}

	pid, err := strconv.Atoi(strings.TrimSpace(string(contents)))
	if err != nil {
		return 0, err
	}

	return pid, nil
}

func isRunningPid(pid int) bool {
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}

	if err = process.Signal(syscall.Signal(0)); err != nil {
		return false
	}

	return true
}

func writePid() {
	pidPath := viper.GetString(mainThreadName + ".pid_file")
	pid := []byte(strconv.Itoa(os.Getpid()))

	if err := ioutil.WriteFile(pidPath, pid, 0644); err != nil {
		log.Fatalf("[%s] error creating pidfile: %s", mainThreadName, err)
	}
}
