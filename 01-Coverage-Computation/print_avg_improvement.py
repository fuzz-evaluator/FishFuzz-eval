from pathlib import Path
import json
import re
from typing import Dict, List
from collections import defaultdict
import statistics


def compute_total_coverage(data: Dict[str, List[int]]) -> int:
    seen_edges = set()
    for ts, covered_edges in sorted(data.items()):
        if int(ts) > (1000 * 3600 * 24):
            continue
        seen_edges |= set(covered_edges)
    return len(seen_edges)


def main():
    result = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    results_dir = Path("./eval-results/")

    for coverage_binary in ["afl", "ffafl"]:
        for run in results_dir.glob(f"collected-runs-*/coverage/{coverage_binary}"):
            run_index = int(
                re.search("collected-runs-([0-9]+)", run.as_posix()).group(1)
            )
            assert run_index is not None
            for target_cov_path in run.glob("*.cov"):
                target_name = target_cov_path.with_suffix("").name
                print(f"Processing {run_index} for target {target_name}")
                data = json.loads(target_cov_path.read_text())

                for fuzzer, fuzzer_cov_data in data.items():
                    coverage_in_edges = compute_total_coverage(fuzzer_cov_data)
                    result[coverage_binary][fuzzer][target_name].append(
                        coverage_in_edges
                    )

    for fuzzer, targets in result["ffafl"].items():
        if fuzzer in ["afl", "aflpp"]:
            continue
        print(f"\n\n########## Fuzzer: {fuzzer}")

        all_differences_in_percent = []
        for target, target_results in targets.items():
            assert len(target_results) == 10

            if statistics.mean(result["ffafl"]["aflpp"][target]) > statistics.mean(
                result["ffafl"]["afl"][target]
            ):
                best_comp = "aflpp"
            else:
                best_comp = "afl"

            competitor_mean_ffafl = statistics.mean(result["ffafl"][best_comp][target])
            self_mean_ffafl = statistics.mean(result["ffafl"][fuzzer][target])
            improvement_ffafl = (self_mean_ffafl / competitor_mean_ffafl - 1) * 100
            improvement_ffafl = round(improvement_ffafl, 2)

            competitor_mean_afl = statistics.mean(result["afl"][best_comp][target])
            self_mean_afl = statistics.mean(result["afl"][fuzzer][target])
            improvement_afl = (self_mean_afl / competitor_mean_afl - 1) * 100
            improvement_afl = round(improvement_afl, 2)

            diff_in_percent = (1 - improvement_afl / improvement_ffafl) * 100 * -1
            all_differences_in_percent.append(diff_in_percent)

            print(f"target: {target:<10}")
            print(f"Improvement on FishFuzz AFL coverage binary : {improvement_ffafl}%")
            print(f"Improvement on AFL coverage binary          : {improvement_afl}%")
            print(
                f"Difference                                  : {improvement_afl-improvement_ffafl:.2f}"
            )
            print(
                f"Difference in %                             : {diff_in_percent:.2f}%"
            )
            print()

        differences_in_percent_avg = statistics.mean(all_differences_in_percent)
        print(
            f"Average difference from FishFuzz AFL coverage binary compared to AFL coverage binary (negative means lower coverage compared to the paper's way of measuring coverage): {differences_in_percent_avg:.2f}%"
        )


if __name__ == "__main__":
    main()
