package summary

import "errors"

var ErrInvalidWindow = errors.New("summary_window_invalid")

type Snapshot struct {
	WindowDays int      `json:"window_days"`
	Timezone   string   `json:"timezone"`
	Coverage   Coverage `json:"coverage"`
	Quality    Quality  `json:"quality"`
	Metrics    []Metric `json:"metrics"`
}

type Coverage struct {
	FirstDay     *string `json:"first_day"`
	LastDay      *string `json:"last_day"`
	DaysWithData int     `json:"days_with_data"`
	WindowStart  string  `json:"window_start"`
	WindowEnd    string  `json:"window_end"`
}

type Quality struct {
	ImportState               string   `json:"import_state"`
	ImportTimezone            *string  `json:"import_timezone"`
	VerifiedFileCount         int      `json:"verified_file_count"`
	SkippedDuplicateFileCount int      `json:"skipped_duplicate_file_count"`
	NormalizedRecordCount     int64    `json:"normalized_record_count"`
	WarningCodes              []string `json:"warning_codes"`
	SourceFamilies            []string `json:"source_families"`
}

type Metric struct {
	Day              string `json:"day"`
	Steps            int64  `json:"steps"`
	ActiveMinutes    int    `json:"active_minutes"`
	SleepMinutes     int    `json:"sleep_minutes"`
	Workouts         int    `json:"workouts"`
	HeartRateSamples int64  `json:"heart_rate_samples"`
	DataAvailable    bool   `json:"data_available"`
}

func ValidWindow(value int) bool {
	return value == 7 || value == 28 || value == 90
}
