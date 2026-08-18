// Shared data model for collected workout reports, validation, and analysis.
//
// Producers (collect, the synthetic fixture) fill every field, using null for
// values a FIT export did not carry; consumers treat fields as optional so
// hand-built partial reports in tests type-check without fabricating data.

export interface ReportSummary {
    elapsed?: number;
    timer?: number;
    avg_hr?: number | null;
    max_hr?: number | null;
    sets?: number;
    movement?: string;
    side?: string;
    equipment?: string | null;
    date?: string | null;
    work_seconds?: number;
    rest_seconds?: number;
    valid_sets?: number;
}

export interface ReportLap {
    lap?: number;
    start?: number;
    end?: number;
    set?: number;
    phase?: string;
    duration?: number;
    elapsed?: number;
    movement?: string;
    side?: string;
    weight?: number | null;
    smoothness?: number | null;
    swings?: number | null;
    exposure?: number | null;
    motion_peak?: number | null;
    active_seconds?: number | null;
    weight_volume?: number | null;
}

export interface ReportPoint {
    t: number;
    hr?: number | null;
    rms?: number | null;
    peak?: number | null;
    zc?: number | null;
    swing_total?: number | null;
    swing_event?: number | null;
    swing_cadence?: number | null;
    smoothness_score?: number | null;
}

export interface Report {
    summary: ReportSummary;
    laps: ReportLap[];
    records: ReportPoint[];
    quality?: ValidationResult;
    analysis?: Analysis;
}

export type Severity = "error" | "warning" | "info";

export interface Finding {
    severity: Severity;
    code: string;
    message: string;
    deduction: number;
    target: string | null;
}

export type ValidationStatus = "healthy" | "usable_with_gaps" | "invalid";

export interface ValidationResult {
    status: ValidationStatus;
    score: number;
    counts: { errors: number; warnings: number };
    coverage: { motion: number; heart_rate: number };
    observed: {
        laps: number;
        work_laps: number;
        rest_laps: number;
        motion_samples: number;
        heart_rate_samples: number;
        swing_samples: number;
        smoothness_samples: number;
    };
    findings: Finding[];
}

export type Confidence = "high" | "medium" | "low" | "insufficient";

export interface Signal {
    code: string;
    label: string;
    status: "available" | "unavailable";
    value: number | null;
    unit: string | null;
    direction: string;
    confidence: Confidence;
    samples: number;
    message: string;
    early?: number;
    late?: number;
    left?: number;
    right?: number;
    coverage?: number;
}

export interface Analysis {
    signals: Signal[];
    available: number;
    disclaimer: string;
}
