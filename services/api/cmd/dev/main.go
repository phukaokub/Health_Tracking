// Command dev starts the complete local API development stack. It is not a
// deployed application command; cmd/api remains the production-like API entry.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	googleClientID     = "SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID"
	googleClientSecret = "SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET"
)

type supabaseStatus struct {
	APIURL         string `json:"API_URL"`
	PublishableKey string `json:"PUBLISHABLE_KEY"`
}

func main() {
	checkOnly := flag.Bool("check-only", false, "configure and verify local dependencies without starting the API")
	flag.Parse()

	if err := run(*checkOnly); err != nil {
		fmt.Fprintln(os.Stderr, "[local] Error:", err)
		os.Exit(1)
	}
}

func run(checkOnly bool) error {
	repositoryRoot, err := findRepositoryRoot()
	if err != nil {
		return err
	}

	googleValues, err := readGoogleValues(filepath.Join(repositoryRoot, ".env.local"))
	if err != nil {
		return err
	}

	localEnv := withEnvironment(os.Environ(), googleValues)
	npx := "npx"
	if runtime.GOOS == "windows" {
		npx = "npx.cmd"
	}

	fmt.Println("[local] Loading local Google OAuth credentials from .env.local.")
	fmt.Println("[local] Restarting local Supabase (local data is preserved).")
	_ = runQuiet(repositoryRoot, localEnv, npx, "--yes", "supabase@2.109.1", "stop")
	if err := runQuiet(repositoryRoot, localEnv, npx, "--yes", "supabase@2.109.1", "start"); err != nil {
		return errors.New("unable to start local Supabase; run 'npx supabase start' from the repository root for diagnostics")
	}

	status, err := getSupabaseStatus(repositoryRoot, localEnv, npx)
	if err != nil {
		return err
	}
	if strings.TrimSpace(status.APIURL) == "" || strings.TrimSpace(status.PublishableKey) == "" {
		return errors.New("local Supabase status did not provide an API URL and publishable key")
	}

	supabaseURL := strings.TrimRight(status.APIURL, "/")
	apiEnv := withEnvironment(localEnv, map[string]string{
		"SUPABASE_URL":             supabaseURL,
		"SUPABASE_PUBLISHABLE_KEY": status.PublishableKey,
		"SUPABASE_JWT_ISSUER":      supabaseURL + "/auth/v1",
		"SUPABASE_JWT_AUDIENCE":    "authenticated",
		"WEB_ORIGIN":               "http://localhost:3000",
	})

	fmt.Println("[local] Supabase is ready; local API environment is configured.")
	if checkOnly {
		return nil
	}

	apiDirectory := filepath.Join(repositoryRoot, "services", "api")
	fmt.Println("[local] Starting API at http://localhost:8080.")
	command := exec.Command("go", "run", "./cmd/api")
	command.Dir = apiDirectory
	command.Env = apiEnv
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command.Run()
}

func findRepositoryRoot() (string, error) {
	directory, err := os.Getwd()
	if err != nil {
		return "", err
	}
	directory, err = filepath.Abs(directory)
	if err != nil {
		return "", err
	}

	for {
		if info, err := os.Stat(filepath.Join(directory, "supabase", "config.toml")); err == nil && !info.IsDir() {
			return directory, nil
		}
		parent := filepath.Dir(directory)
		if parent == directory {
			return "", errors.New("could not find repository root containing supabase/config.toml")
		}
		directory = parent
	}
}

func readGoogleValues(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, errors.New("missing .env.local; copy .env.local.example to .env.local and add the local Google OAuth client ID and secret")
		}
		return nil, err
	}
	defer file.Close()

	values := make(map[string]string)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		name, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		name = strings.TrimSpace(name)
		if name == googleClientID || name == googleClientSecret {
			values[name] = strings.Trim(strings.TrimSpace(value), "\"'")
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	missing := make([]string, 0, 2)
	for _, name := range []string{googleClientID, googleClientSecret} {
		if strings.TrimSpace(values[name]) == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("missing local Google OAuth values in .env.local: %s", strings.Join(missing, ", "))
	}
	return values, nil
}

func getSupabaseStatus(directory string, environment []string, npx string) (supabaseStatus, error) {
	command := exec.Command(npx, "--yes", "supabase@2.109.1", "status", "--output", "json")
	command.Dir = directory
	command.Env = environment
	command.Stderr = io.Discard
	output, err := command.Output()
	if err != nil {
		return supabaseStatus{}, errors.New("unable to read local Supabase status")
	}

	var status supabaseStatus
	if err := json.Unmarshal(output, &status); err != nil {
		return supabaseStatus{}, errors.New("local Supabase returned an unreadable status response")
	}
	return status, nil
}

func runQuiet(directory string, environment []string, program string, arguments ...string) error {
	command := exec.Command(program, arguments...)
	command.Dir = directory
	command.Env = environment
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	return command.Run()
}

func withEnvironment(base []string, values map[string]string) []string {
	result := make([]string, 0, len(base)+len(values))
	for _, entry := range base {
		name, _, found := strings.Cut(entry, "=")
		if !found {
			continue
		}
		if _, replaced := values[name]; !replaced {
			result = append(result, entry)
		}
	}
	for name, value := range values {
		result = append(result, name+"="+value)
	}
	return result
}
