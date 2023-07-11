# %%
import json
import re
import math
import datetime
import shutil
from pathlib import Path
from typing import Dict, List, Set
from collections import defaultdict

import altair as alt
import pandas as pd

alt.data_transformers.disable_max_rows()


RUN_DURATION_IN_S = 3600 * 24
assert (RUN_DURATION_IN_S % 60) == 0
RUN_DURATION_IN_M = RUN_DURATION_IN_S // 60

RESULT_DIR = Path("/data/01-Coverage-Computation/eval-results/")
CHARTS_DIR = Path("/data/01-Coverage-Computation/charts")
CHARTS_SVG_DIR = CHARTS_DIR / "svg"
CHARTS_PNG_DIR = CHARTS_DIR / "png"


# Input: `data` is a mapping of <timestamp in ms> to [ids of found edges]
# Output: Mapping of second (0..RUN_DURATION_IN_S) to total number of found edges at this point in time.
def compute_coverage_over_time(data: Dict[str, List[int]]) -> Dict[int, int]:
    ts_to_num_covered_edges: Dict[int, int] = dict()

    # Edges we saw so far. After processing all samples, this contains all covered edges.
    seen_edges: Set[int] = set()
    for ts_in_ms, covered_edges in sorted(data.items(), key=lambda e: int(e[0])):
        ts_in_ms = int(ts_in_ms)
        ts_in_s = ts_in_ms // 1000

        # We are only interested in the first RUN_DURATION_IN_S seconds.
        if ts_in_s > RUN_DURATION_IN_S:
            continue
        seen_edges |= set(covered_edges)
        ts_to_num_covered_edges[ts_in_s] = len(seen_edges)

    # Fill gaps, such that we have a mapping for each second from 0 to RUN_DURATION_IN_S
    edges_covered_until_now = None
    for second in range(RUN_DURATION_IN_S):
        if (edges_covered := ts_to_num_covered_edges.get(second)) is not None:
            assert edges_covered_until_now is None or (
                edges_covered >= edges_covered_until_now
            ), f"edges_covered={edges_covered}, edges_covered_until_now={edges_covered_until_now}"
            edges_covered_until_now = edges_covered
        else:
            ts_to_num_covered_edges[second] = edges_covered_until_now

    return ts_to_num_covered_edges


# Parse the FishFuzz coverage data produced using `coverage_binary`.
# Returns: Mapping of <target binary> -> (<fuzzer name> -> [[<second> -> <total edge count cov>], ...])
def parse_runs(coverage_binary: str):
    assert coverage_binary in ["afl", "ffafl", "AFL-map-size-18"]
    fuzzer_target_runs = defaultdict(lambda: defaultdict(list))

    for run in RESULT_DIR.glob(f"collected-runs-*/coverage/{coverage_binary}"):
        print(run)
        run_index = int(re.search("collected-runs-([0-9]+)", run.as_posix()).group(1))
        assert run_index is not None

        for target_cov_path in run.glob("*.cov"):
            target_name = target_cov_path.with_suffix("").name
            print(f"Processing run {run_index} of target {target_name}")
            data = json.loads(target_cov_path.read_text())

            for fuzzer, fuzzer_cov_data in data.items():
                ts_to_num_covered_edges = compute_coverage_over_time(fuzzer_cov_data)
                fuzzer_target_runs[fuzzer][target_name].append(ts_to_num_covered_edges)

    return fuzzer_target_runs


# Data layout: *_coverage_runs[fuzzer][target] -> List[Dict[int, int]],
# where Dict[int, int] is a mapping of 0..RUNTIME_IN_S to number of covered edges.
afl_coverage_runs = parse_runs("afl")
ffafl_coverage_runs = parse_runs("ffafl")
# afl_18_map_coverage_runs = parse_runs('AFL-map-size-18')

# %%

TARGETS = ["cflow", "cxxfilt", "tic", "mujs", "w3m", "dwarfdump", "mutool"]

# Mapping from used coverage binary to runs
coverage_binary_to_runs = dict()
coverage_binary_to_runs["afl"] = afl_coverage_runs
coverage_binary_to_runs["ffafl"] = ffafl_coverage_runs


def calculate_intervals(data: pd.DataFrame, interval_width: float = 1) -> pd.DataFrame:
    # minute -> [y value_0, ...] (length equals number of repetitions)
    y_values_for_minute = data.groupby("min")["y"].apply(list)
    interval_width_in_elms = math.floor(
        math.floor(len(y_values_for_minute[0]) * interval_width) / 2
    )

    result_interval_frame = defaultdict(list)

    # Used later for creating the frame index
    frame_index = []
    for minute, y_values in y_values_for_minute.items():
        # Sort all y values at the given minute and pick the upper and lower element.
        elm_cnt = len(y_values)
        y_values = sorted(y_values)
        median_index = elm_cnt // 2
        if interval_width == 1.0:
            interval_lower_bound = y_values[0]
            interval_upper_bound = y_values[len(y_values)-1]
        else:
            interval_lower_bound = y_values[max(median_index - interval_width_in_elms, 0)]
            interval_upper_bound = y_values[
                min(median_index + interval_width_in_elms, len(y_values) - 1)
            ]

        assert interval_lower_bound is not None
        assert interval_upper_bound is not None

        frame_index.append(minute)
        result_interval_frame["min"].append(minute)
        result_interval_frame["interval_lower"].append(interval_lower_bound)
        result_interval_frame["interval_upper"].append(interval_upper_bound)
    return pd.DataFrame(result_interval_frame, index=frame_index)


def build_coverage_data_frame(
    run_id: int, cov_binary: str, fuzzer: str, second_to_edge_cnt: Dict[int, int]
) -> pd.DataFrame:
    frame = defaultdict(list)
    for minute in range(RUN_DURATION_IN_M):
        frame["run_id"].append(run_id)
        frame["min"].append(minute)
        frame["x"].append(datetime.datetime.utcfromtimestamp(minute * 60))
        frame["y"].append(second_to_edge_cnt[minute * 60])
        frame["cov_binary"].append(cov_binary)
        frame["fuzzer"].append(fuzzer)
    return pd.DataFrame(frame)


def set_style(chart: alt.Chart) -> alt.Chart:
    return (
        chart.configure(font="cmr10")
        .configure_axis(
            labelFontSize=18,
            titleFontSize=18,
        )
        .configure_title(
            fontSize=18,
        )
        .configure_legend(
            titleFontSize=20,
            labelFontSize=18,
            labelLimit=0,
        )
    )


CHARTS_DIR.mkdir(exist_ok=True)
CHARTS_SVG_DIR.mkdir(exist_ok=True)
CHARTS_PNG_DIR.mkdir(exist_ok=True)

# FUZZERS_TO_PLOT = ['aflpp', 'ffapp', 'afl', 'ffafl']
FUZZERS_TO_PLOT = ["aflpp", "ffapp"]
# FUZZERS_TO_PLOT = ['afl', 'ffafl']

for target in TARGETS:
    frames = []
    for coverage_binary, runs in coverage_binary_to_runs.items():
        for fuzzer, target_cov in runs.items():
            if fuzzer not in FUZZERS_TO_PLOT:
                continue
            # Process all runs for current fuzzer + coverage_binary + target
            target_frames = []
            for run_id, run_data in enumerate(target_cov[target]):
                frame = build_coverage_data_frame(
                    run_id, coverage_binary, fuzzer, run_data
                )
                target_frames.append(frame)
            target_frame = pd.concat(target_frames)
            interval_frame = calculate_intervals(target_frame)
            target_frame = target_frame.merge(interval_frame, on="min")
            frames.append(target_frame)

    merged_frames = pd.concat(frames)

    afl_cov_line_layer = (
        alt.Chart(merged_frames[merged_frames["cov_binary"] == "afl"], title=target)
        .mark_line()
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M"), title="Time [hh:mm]"),
            y=alt.Y("median(y)", title="#Covered Edges"),
            color=alt.Color(f"fuzzer:N", title="Fuzzer"),
            strokeDash=alt.StrokeDash("cov_binary:N", title="Coverage Binary"),
        )
    )

    afl_interval_layer: alt.Chart = (
        alt.Chart(merged_frames[merged_frames["cov_binary"] == "afl"])
        .mark_area(opacity=0.4)
        .encode()
        .encode(
            color=alt.Color(f"fuzzer:N"),
        )
        .transform_window(
            rollingy2="median(interval_upper)",
            rollingy="median(interval_lower)",
            frame=[-50, 50],
        )
        .encode(x=alt.X("x:T"), y=alt.Y("rollingy:Q"), y2="rollingy2")
    )

    ffafl_cov_line_layer = (
        alt.Chart(merged_frames[merged_frames["cov_binary"] == "ffafl"], title=target)
        .mark_line(strokeDash=[0, 5])
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M"), title="Time [hh:mm]"),
            y=alt.Y("median(y)", title="#Covered Edges"),
            color=alt.Color(f"fuzzer:N"),
            strokeDash="cov_binary:N",
        )
    )

    ffafl_interval_layer: alt.Chart = (
        alt.Chart(merged_frames[merged_frames["cov_binary"] == "ffafl"])
        .mark_area(opacity=0.4)
        .encode()
        .encode(
            color=alt.Color(f"fuzzer:N"),
        )
        .transform_window(
            rollingy2="median(interval_upper)",
            rollingy="median(interval_lower)",
            frame=[-50, 50],
        )
        .encode(x=alt.X("x:T"), y=alt.Y("rollingy:Q"), y2="rollingy2")
    )

    chart = (afl_cov_line_layer + afl_interval_layer) + (
        ffafl_cov_line_layer + ffafl_interval_layer
    )
    set_style(chart)
    chart_name = f"{target}"

    svg_dir = CHARTS_SVG_DIR / "vs".join(FUZZERS_TO_PLOT)
    svg_dir.mkdir(exist_ok=True)
    chart.save(svg_dir / f"{chart_name}.svg")

    png_dir = CHARTS_PNG_DIR / "vs".join(FUZZERS_TO_PLOT)
    png_dir.mkdir(exist_ok=True)
    chart.save(png_dir / f"{chart_name}.png", scale_factor=3.0)
