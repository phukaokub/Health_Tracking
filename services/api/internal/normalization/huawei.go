// Package normalization converts approved, sanitized Huawei JSON records into
// canonical wellness samples. It has no provider, database, logging, or raw
// payload retention dependencies.
package normalization

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"
)

const (
	ParserVersion  = "huawei-json-v1"
	MaxInputBytes  = 20 * 1024 * 1024
	MaxRecordBytes = 1 * 1024 * 1024
	MaxRecordCount = 10000
	SourceFamily   = "huawei_health_json"
)

type SafeError struct{ Code string }

func (err *SafeError) Error() string { return err.Code }

type Warning struct {
	Code string `json:"code"`
}

type Sample struct {
	SourceFamily          string    `json:"source_family"`
	SourceType            string    `json:"source_type"`
	SourceRecordHash      string    `json:"source_record_hash"`
	StartedAt             time.Time `json:"started_at"`
	EndedAt               time.Time `json:"ended_at"`
	Unit                  string    `json:"unit"`
	SourceUnit            string    `json:"source_unit"`
	UnitConversionVersion string    `json:"unit_conversion_version"`
	Value                 string    `json:"value"`
	DedupeKey             string    `json:"dedupe_key"`
	ParserVersion         string    `json:"parser_version"`
}

type Result struct {
	Samples       []Sample       `json:"samples"`
	SleepSessions []SleepSession `json:"sleep_sessions"`
	Activities    []Activity     `json:"activities"`
	Workouts      []Workout      `json:"workouts"`
	Warnings      []Warning      `json:"warnings"`
}
type SleepSession struct {
	SourceRecordHash string       `json:"source_record_hash"`
	StartedAt        time.Time    `json:"started_at"`
	EndedAt          time.Time    `json:"ended_at"`
	DurationSeconds  int64        `json:"duration_seconds"`
	DedupeKey        string       `json:"dedupe_key"`
	ParserVersion    string       `json:"parser_version"`
	Stages           []SleepStage `json:"stages"`
}
type SleepStage struct {
	StageCode string    `json:"stage_code"`
	StartedAt time.Time `json:"started_at"`
	EndedAt   time.Time `json:"ended_at"`
	DedupeKey string    `json:"dedupe_key"`
}
type Activity struct {
	SourceRecordHash string    `json:"source_record_hash"`
	ActivityType     string    `json:"activity_type"`
	StartedAt        time.Time `json:"started_at"`
	EndedAt          time.Time `json:"ended_at"`
	DurationSeconds  int64     `json:"duration_seconds"`
	DedupeKey        string    `json:"dedupe_key"`
	ParserVersion    string    `json:"parser_version"`
}
type Workout struct {
	SourceRecordHash   string    `json:"source_record_hash"`
	WorkoutType        string    `json:"workout_type"`
	StartedAt          time.Time `json:"started_at"`
	EndedAt            time.Time `json:"ended_at"`
	DurationSeconds    int64     `json:"duration_seconds"`
	DistanceMetres     string    `json:"distance_metres,omitempty"`
	EnergyKilocalories string    `json:"energy_kilocalories,omitempty"`
	DedupeKey          string    `json:"dedupe_key"`
	ParserVersion      string    `json:"parser_version"`
}

type sourceRecord struct {
	Type               string             `json:"type"`
	RecordID           string             `json:"record_id"`
	StartedAt          string             `json:"started_at"`
	EndedAt            string             `json:"ended_at"`
	Unit               string             `json:"unit"`
	Value              json.RawMessage    `json:"value"`
	Stages             []sourceSleepStage `json:"stages"`
	ActivityType       string             `json:"activity_type"`
	WorkoutType        string             `json:"workout_type"`
	DistanceMetres     json.RawMessage    `json:"distance_metres"`
	EnergyKilocalories json.RawMessage    `json:"energy_kilocalories"`
}
type sourceSleepStage struct {
	Code      string `json:"code"`
	StartedAt string `json:"started_at"`
	EndedAt   string `json:"ended_at"`
}

// ParseHuaweiJSON consumes the records array incrementally. It never returns
// input text in errors and drops unsupported sensitive record families.
func ParseHuaweiJSON(reader io.Reader) (Result, error) {
	decoder := json.NewDecoder(io.LimitReader(reader, MaxInputBytes+1))
	decoder.UseNumber()
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return Result{}, safeJSONError(err)
	}
	var result Result
	foundRecords := false
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return Result{}, safeJSONError(err)
		}
		key, ok := keyToken.(string)
		if !ok {
			return Result{}, &SafeError{Code: "source_schema_unsupported"}
		}
		if key != "records" {
			var discard json.RawMessage
			if err := decoder.Decode(&discard); err != nil {
				return Result{}, safeJSONError(err)
			}
			continue
		}
		foundRecords = true
		if token, err := decoder.Token(); err != nil || token != json.Delim('[') {
			return Result{}, &SafeError{Code: "source_schema_unsupported"}
		}
		for index := 0; decoder.More(); index++ {
			if index >= MaxRecordCount {
				return Result{}, &SafeError{Code: "json_token_too_large"}
			}
			var raw json.RawMessage
			if err := decoder.Decode(&raw); err != nil {
				return Result{}, safeJSONError(err)
			}
			if len(raw) > MaxRecordBytes {
				return Result{}, &SafeError{Code: "json_token_too_large"}
			}
			var record sourceRecord
			if err := json.Unmarshal(raw, &record); err != nil {
				return Result{}, &SafeError{Code: "source_schema_unsupported"}
			}
			if record.Type == "sleep_session" {
				session, warning, err := normalizeSleep(record)
				if err != nil {
					return Result{}, err
				}
				if warning != nil {
					result.Warnings = append(result.Warnings, *warning)
				}
				if session != nil {
					result.SleepSessions = append(result.SleepSessions, *session)
				}
				continue
			}
			if record.Type == "activity" {
				activity, warning, err := normalizeActivity(record)
				if err != nil {
					return Result{}, err
				}
				if warning != nil {
					result.Warnings = append(result.Warnings, *warning)
				}
				if activity != nil {
					result.Activities = append(result.Activities, *activity)
				}
				continue
			}
			if record.Type == "workout_summary" {
				workout, err := normalizeWorkout(record)
				if err != nil {
					return Result{}, err
				}
				result.Workouts = append(result.Workouts, *workout)
				continue
			}
			sample, warning, err := normalizeRecord(record)
			if err != nil {
				return Result{}, err
			}
			if warning != nil {
				result.Warnings = append(result.Warnings, *warning)
			}
			if sample != nil {
				result.Samples = append(result.Samples, *sample)
			}
		}
		if token, err := decoder.Token(); err != nil || token != json.Delim(']') {
			return Result{}, safeJSONError(err)
		}
	}
	if token, err := decoder.Token(); err != nil || token != json.Delim('}') || !foundRecords {
		return Result{}, &SafeError{Code: "source_schema_unsupported"}
	}
	if decoder.More() {
		return Result{}, &SafeError{Code: "source_schema_unsupported"}
	}
	return result, nil
}

func normalizeWorkout(record sourceRecord) (*Workout, error) {
	if record.RecordID == "" || record.WorkoutType == "" {
		return nil, &SafeError{Code: "source_schema_unsupported"}
	}
	s, e1 := time.Parse(time.RFC3339, record.StartedAt)
	e, e2 := time.Parse(time.RFC3339, record.EndedAt)
	if e1 != nil || e2 != nil || !e.After(s) {
		return nil, &SafeError{Code: "timestamp_invalid"}
	}
	h := hash(record.RecordID)
	workout := &Workout{SourceRecordHash: h, WorkoutType: record.WorkoutType, StartedAt: s.UTC(), EndedAt: e.UTC(), DurationSeconds: int64(e.Sub(s).Seconds()), ParserVersion: ParserVersion}
	for _, value := range []struct {
		raw    json.RawMessage
		target *string
	}{{record.DistanceMetres, &workout.DistanceMetres}, {record.EnergyKilocalories, &workout.EnergyKilocalories}} {
		if len(value.raw) == 0 {
			continue
		}
		parsed, err := strconv.ParseFloat(strings.TrimSpace(string(value.raw)), 64)
		if err != nil || parsed < 0 {
			return nil, &SafeError{Code: "metric_mapping_unknown"}
		}
		*value.target = strconv.FormatFloat(parsed, 'f', -1, 64)
	}
	workout.DedupeKey = hash(strings.Join([]string{"v1", SourceFamily, "workout", h, record.WorkoutType, workout.StartedAt.Format(time.RFC3339Nano), workout.EndedAt.Format(time.RFC3339Nano), workout.DistanceMetres, workout.EnergyKilocalories}, "|"))
	return workout, nil
}

func normalizeActivity(record sourceRecord) (*Activity, *Warning, error) {
	if record.RecordID == "" || record.ActivityType == "" {
		return nil, nil, &SafeError{Code: "source_schema_unsupported"}
	}
	start, e1 := time.Parse(time.RFC3339, record.StartedAt)
	end, e2 := time.Parse(time.RFC3339, record.EndedAt)
	if e1 != nil || e2 != nil || !end.After(start) {
		return nil, nil, &SafeError{Code: "timestamp_invalid"}
	}
	if record.ActivityType != "walking" && record.ActivityType != "running" && record.ActivityType != "cycling" && record.ActivityType != "other" {
		return nil, &Warning{Code: "metric_mapping_unknown"}, nil
	}
	h := hash(record.RecordID)
	return &Activity{SourceRecordHash: h, ActivityType: record.ActivityType, StartedAt: start.UTC(), EndedAt: end.UTC(), DurationSeconds: int64(end.Sub(start).Seconds()), DedupeKey: hash(strings.Join([]string{"v1", SourceFamily, "activity", h, record.ActivityType, start.UTC().Format(time.RFC3339Nano), end.UTC().Format(time.RFC3339Nano)}, "|")), ParserVersion: ParserVersion}, nil, nil
}

func normalizeSleep(record sourceRecord) (*SleepSession, *Warning, error) {
	if record.RecordID == "" {
		return nil, nil, &SafeError{Code: "source_schema_unsupported"}
	}
	start, err := time.Parse(time.RFC3339, record.StartedAt)
	if err != nil {
		return nil, nil, &SafeError{Code: "timestamp_invalid"}
	}
	end, err := time.Parse(time.RFC3339, record.EndedAt)
	if err != nil || !end.After(start) {
		return nil, nil, &SafeError{Code: "timestamp_invalid"}
	}
	recordHash := hash(record.RecordID)
	session := &SleepSession{SourceRecordHash: recordHash, StartedAt: start.UTC(), EndedAt: end.UTC(), DurationSeconds: int64(end.Sub(start).Seconds()), ParserVersion: ParserVersion}
	session.DedupeKey = hash(strings.Join([]string{"v1", SourceFamily, "sleep_session", recordHash, session.StartedAt.Format(time.RFC3339Nano), session.EndedAt.Format(time.RFC3339Nano)}, "|"))
	for _, stage := range record.Stages {
		if stage.Code != "awake" && stage.Code != "light" && stage.Code != "deep" && stage.Code != "rem" {
			return nil, &Warning{Code: "sleep_stage_unknown"}, nil
		}
		stageStart, e1 := time.Parse(time.RFC3339, stage.StartedAt)
		stageEnd, e2 := time.Parse(time.RFC3339, stage.EndedAt)
		if e1 != nil || e2 != nil || stageEnd.Before(stageStart) || stageStart.Before(start) || stageEnd.After(end) {
			return nil, nil, &SafeError{Code: "timestamp_invalid"}
		}
		key := hash(strings.Join([]string{"v1", session.DedupeKey, stage.Code, stageStart.UTC().Format(time.RFC3339Nano), stageEnd.UTC().Format(time.RFC3339Nano)}, "|"))
		session.Stages = append(session.Stages, SleepStage{StageCode: stage.Code, StartedAt: stageStart.UTC(), EndedAt: stageEnd.UTC(), DedupeKey: key})
	}
	return session, nil, nil
}

func normalizeRecord(record sourceRecord) (*Sample, *Warning, error) {
	if record.Type == "ecg" || record.Type == "workout_route" {
		return nil, &Warning{Code: "sensitive_record_excluded"}, nil
	}
	mapping, supported := scalarMappings[record.Type]
	if !supported {
		return nil, &Warning{Code: "metric_mapping_unknown"}, nil
	}
	if record.RecordID == "" {
		return nil, nil, &SafeError{Code: "unit_unsupported"}
	}
	start, err := time.Parse(time.RFC3339, record.StartedAt)
	if err != nil {
		return nil, nil, &SafeError{Code: "timestamp_invalid"}
	}
	end := start
	if record.EndedAt != "" {
		end, err = time.Parse(time.RFC3339, record.EndedAt)
		if err != nil || end.Before(start) {
			return nil, nil, &SafeError{Code: "timestamp_invalid"}
		}
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(string(record.Value)), 64)
	if err != nil {
		return nil, nil, &SafeError{Code: "metric_mapping_unknown"}
	}
	value, ok := mapping.convert(record.Unit, value)
	if !ok {
		return nil, nil, &SafeError{Code: "unit_unsupported"}
	}
	canonicalValue := strconv.FormatFloat(value, 'f', -1, 64)
	recordHash := hash(record.RecordID)
	identity := strings.Join([]string{"v1", SourceFamily, record.Type, recordHash, start.UTC().Format(time.RFC3339Nano), end.UTC().Format(time.RFC3339Nano), mapping.unit, canonicalValue}, "|")
	return &Sample{SourceFamily: SourceFamily, SourceType: record.Type, SourceRecordHash: recordHash, StartedAt: start.UTC(), EndedAt: end.UTC(), Unit: mapping.unit, SourceUnit: record.Unit, UnitConversionVersion: "v1", Value: canonicalValue, DedupeKey: hash(identity), ParserVersion: ParserVersion}, nil, nil
}

type scalarMapping struct {
	unit        string
	conversions map[string]func(float64) float64
}

func (mapping scalarMapping) convert(unit string, value float64) (float64, bool) {
	conversion, ok := mapping.conversions[unit]
	if !ok || value < 0 {
		return 0, false
	}
	return conversion(value), true
}
func same(value float64) float64 { return value }

var scalarMappings = map[string]scalarMapping{
	"heart_rate": {"bpm", map[string]func(float64) float64{"bpm": same}}, "resting_heart_rate": {"bpm", map[string]func(float64) float64{"bpm": same}},
	"hrv": {"milliseconds", map[string]func(float64) float64{"ms": same}}, "stress": {"source_score", map[string]func(float64) float64{"huawei_score": same}},
	"skin_temperature": {"degrees_celsius", map[string]func(float64) float64{"celsius": same, "fahrenheit": func(v float64) float64 { return (v - 32) * 5 / 9 }}},
	"spo2":             {"percent", map[string]func(float64) float64{"percent": same, "fraction": func(v float64) float64 { return v * 100 }}},
	"steps":            {"count", map[string]func(float64) float64{"count": same}}, "calories": {"kilocalories", map[string]func(float64) float64{"kcal": same, "kj": func(v float64) float64 { return v / 4.184 }}},
	"distance": {"metres", map[string]func(float64) float64{"metres": same, "kilometres": func(v float64) float64 { return v * 1000 }}}, "floors": {"count", map[string]func(float64) float64{"count": same}},
	"active_duration":    {"seconds", map[string]func(float64) float64{"seconds": same, "minutes": func(v float64) float64 { return v * 60 }, "milliseconds": func(v float64) float64 { return v / 1000 }}},
	"exercise_intensity": {"source_score", map[string]func(float64) float64{"huawei_score": same}},
}

func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func safeJSONError(err error) error {
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
		return &SafeError{Code: "json_truncated"}
	}
	var syntax *json.SyntaxError
	if errors.As(err, &syntax) {
		return &SafeError{Code: "json_truncated"}
	}
	if err == nil {
		return &SafeError{Code: "source_schema_unsupported"}
	}
	return &SafeError{Code: "source_schema_unsupported"}
}

func SafeCode(err error) string {
	var safe *SafeError
	if errors.As(err, &safe) {
		return safe.Code
	}
	return fmt.Sprintf("%s", "source_schema_unsupported")
}
