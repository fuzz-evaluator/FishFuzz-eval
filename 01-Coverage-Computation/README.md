# 01-Coverage-Computation

This experiment's purpose is to showcase that it makes a considerable difference whether coverage for different fuzzers is computed using instrumented binaries or uninstrumented binaries.

To this end, we reproduce the two-stage experiment (Table 5) of FishFuzz. Our experiment includes seven targets that are run for AFL, AFL++ and the patched FishFuzz equivalences, namely FishFuzz (based on AFL) and FishFuzz++ (based on AFL++).
Based on the fuzzing runs, the achieved coverage is computed in two ways that both use `afl-showmap` (from vanilla AFL)
    1. Based on a binary that contains AFL coverage instrumentation *and* FishFuzz' instrumentation (as was used in the FishFuzz paper).
    2. Based on a binary only containing AFL coverage instrumentation.

## Running the experiments and computing coverage
In order to run the experiments, the following steps need to be performed:
  1. Execute `prepare.sh` in the parent directory (if not done already).
  2. Adapt the configurations section of `run-eval.sh` (such as setting the number of available CPUs, desired trials, ...)
  3. Execute `./run-eval.sh`. This starts the evaluation and terminates when all jobs are finished.
  4. The results will be stored in `./eval-results`
  5. The results must be combined (by merging the `eval-results` directories) if `run-eval.sh` was executed on multiple machines. Ensure you configured different values for `FIRST_TRIAL` and `LAST_TRIAL` in `run-eval.sh`.
  6. Execute `./run-postprocessing.sh $PWD/eval-results` to compute the coverage. This will take about an hour if there are 10 or more cores available.
  7. Coverage results will be available for each coverage binary (afl and ffafl) in `eval-results/collected-runs-*/coverage`. The format is the one used by FishFuzz's artifact.
  8. Based on the data, plots or statistics can be generated (see below)


## Generating the plot
1. Execute `prepare.sh` in the parent directory (if not done already).
2. Run `./plot.sh` to start the plotting. After termination, the plots are located in `./charts`.

## Generating statistics (coverage differences)
1. Execute `python3 print_avg_improvement.py`. This will give you output similar to the following:

```
########## Fuzzer: ffafl
target: cflow
Improvement on FishFuzz AFL coverage binary : 2.25%
Improvement on AFL coverage binary          : 1.83%
Difference                                  : -0.42
Difference in %                             : -18.67%

target: cxxfilt
Improvement on FishFuzz AFL coverage binary : 4.41%
Improvement on AFL coverage binary          : -2.29%
Difference                                  : -6.70
Difference in %                             : -151.93%

target: tic
Improvement on FishFuzz AFL coverage binary : 5.06%
Improvement on AFL coverage binary          : 1.12%
Difference                                  : -3.94
Difference in %                             : -77.87%

target: mujs
Improvement on FishFuzz AFL coverage binary : 1.06%
Improvement on AFL coverage binary          : -0.46%
Difference                                  : -1.52
Difference in %                             : -143.40%

target: w3m
Improvement on FishFuzz AFL coverage binary : -24.05%
Improvement on AFL coverage binary          : -24.91%
Difference                                  : -0.86
Difference in %                             : 3.58%

target: dwarfdump
Improvement on FishFuzz AFL coverage binary : 1.58%
Improvement on AFL coverage binary          : 1.28%
Difference                                  : -0.30
Difference in %                             : -18.99%

target: mutool
Improvement on FishFuzz AFL coverage binary : 2.76%
Improvement on AFL coverage binary          : 1.29%
Difference                                  : -1.47
Difference in %                             : -53.26%

Average difference from FishFuzz AFL coverage binary compared to AFL coverage binary (negative means lower coverage compared to the paper's way of measuring coverage): -65.79%


########## Fuzzer: ffapp
target: cflow
Improvement on FishFuzz AFL coverage binary : 0.53%
Improvement on AFL coverage binary          : 0.13%
Difference                                  : -0.40
Difference in %                             : -75.47%

target: cxxfilt
Improvement on FishFuzz AFL coverage binary : 8.44%
Improvement on AFL coverage binary          : 1.69%
Difference                                  : -6.75
Difference in %                             : -79.98%

target: tic
Improvement on FishFuzz AFL coverage binary : 6.16%
Improvement on AFL coverage binary          : 2.04%
Difference                                  : -4.12
Difference in %                             : -66.88%

target: mujs
Improvement on FishFuzz AFL coverage binary : 3.6%
Improvement on AFL coverage binary          : 2.83%
Difference                                  : -0.77
Difference in %                             : -21.39%

target: w3m
Improvement on FishFuzz AFL coverage binary : 0.57%
Improvement on AFL coverage binary          : 0.28%
Difference                                  : -0.29
Difference in %                             : -50.88%

target: dwarfdump
Improvement on FishFuzz AFL coverage binary : -2.51%
Improvement on AFL coverage binary          : -2.29%
Difference                                  : 0.22
Difference in %                             : -8.76%

target: mutool
Improvement on FishFuzz AFL coverage binary : 1.88%
Improvement on AFL coverage binary          : 0.76%
Difference                                  : -1.12
Difference in %                             : -59.57%

Average difference from FishFuzz AFL coverage binary compared to AFL coverage binary (negative means lower coverage compared to the paper's way of measuring coverage): -51.85%
```


## Layout
- `Dockerfile`: The Dockerfile used to build the images this experiment is based on.
- `prepare.sh`: Build the Docker image for this experiment.
- `run-eval.sh`: Run the evaluation to produce the RAW data. Results are stored in the folder `eval-results`.
- `run-postprocessing.sh`: Compute the coverage for the data produced by the `run-eval.sh` script.
- `postprocess.sh`: Computed coverage for each run. This script is called by `run-postprocessing.sh` and does not need to be called manually.
- `print_avg_improvement.py`: Print statistics, such as coverage differences between the coverage binaries.
- `plot.sh`: Generate the plots used in the parent README.md.
- `scripts/plot_runs.py`: Plot the graphs used in the parent README.md. This script is used by `plot.sh`.