# Plasticity Code

`Plasticity_Code.m` is the main MATLAB script used for the MECH0026 plasticity coursework workflow. It processes tensile-test data for aluminium, identifies key material points such as yield and ultimate tensile strength, builds undamaged and damage-based true stress responses, and can compare those results against post-processing data from FEA runs.

## What the script does

- Reads engineering stress-strain data from `Aluminium - Engineering stress_strain.xlsx`.
- Converts engineering data to true stress-strain form.
- Computes the linear elastic fit, yield point, engineering UTS, and Considere necking criterion.
- Builds an undamaged true response and a damage evolution curve from UTS to rupture.
- Writes processed results back into the Excel workbook on the `Processed data` and `Displacement_By_Element_Size` sheets.
- Exports figures to the local `Figures/` folder.
- Optionally reads mesh-convergence and damage-evolution data from `Convergence Jobs/` and `FEA RESULTS/` for post-FEA plots.

## Run modes

The top of the script contains two main switches:

- `Run_Pre_FEA_Pipeline`: runs the material-data analysis and pre-FEA plots.
- `Run_Post_FEA_Pipeline`: loads available FEA result folders and generates comparison/convergence plots.

Other useful settings:

- `Element_Size_L`: converged element size used to convert post-UTS plastic strain to equivalent plastic displacement.
- `Enable_Damaged_Model_Post_Plots`: enables extra damaged-model post-processing plots when the required data are available.
- `Use_Separate_Damaged_Data_Root`: points the damaged-model reader to a different results directory if needed.

## Inputs and assumptions

- The script expects the first sheet of the Excel workbook to contain the raw engineering strain and stress data in the first two numeric columns.
- The workbook is updated in place, so avoid keeping it open in Excel while the script is running.
- The script currently adds a hard-coded utilities path with `addpath(...)`; update that line if the repo is moved.
- Workbook cleanup uses Excel COM automation (`actxserver`), so the reporting workflow is Windows-specific.

## Typical outputs

- Updated Excel workbook with processed material data.
- PNG and MATLAB `.fig` files in `Figures/`.
- Optional FEA comparison, mesh convergence, runtime, and damage-evolution plots when post-FEA data are present.

## Usage

Open `Plasticity_Code.m` in MATLAB, set the pipeline flags at the top of the file, then run the script from the `Tex/Script` directory or with that folder on the MATLAB path.
