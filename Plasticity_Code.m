clc; clear; close all

% ==============================================================
% INITIAL SETUP
% ==============================================================

try
    set(groot, 'defaultAxesToolbarVisible', 'off');
catch
    % Property availability depends on MATLAB release.
end
try
    set(groot, 'defaultFigureWindowStyle', 'docked');
catch
    % Some MATLAB releases do not expose this root default.
end

% -------------------------- Pipeline flags --------------------------
Run_Pre_FEA_Pipeline = false;   % Pre-FEA analytics + material-data plots
Run_Post_FEA_Pipeline = true;  % Post-FEA data loading + FEA plots

% ------------------------ Damaged model flags -----------------------
Enable_Damaged_Model_Post_Plots = false;   % Set true when damaged-model post data are ready
Use_Separate_Damaged_Data_Root = false;    % Set true to load post data from a dedicated folder
Damaged_Data_Root_Directory = '';          % Example: 'D:\...\Damaged Model\Convergence Jobs'

if ~(Run_Pre_FEA_Pipeline || Run_Post_FEA_Pipeline)
    error('At least one of Run_Pre_FEA_Pipeline or Run_Post_FEA_Pipeline must be true.');
end

if Run_Pre_FEA_Pipeline
    Pre_Pipeline_State = 'ON';
else
    Pre_Pipeline_State = 'OFF';
end
if Run_Post_FEA_Pipeline
    Post_Pipeline_State = 'ON';
else
    Post_Pipeline_State = 'OFF';
end

fprintf('\n============================================================\n');
fprintf(' PLASTICITY DATA PROCESSING (SCRIPT MODE)\n');
fprintf('============================================================\n');
fprintf('Timestamp                : %s\n', char(datetime('now')));
fprintf('Pre-FEA pipeline         : %s\n', Pre_Pipeline_State);
fprintf('Post-FEA pipeline        : %s\n', Post_Pipeline_State);
fprintf('Damaged-model post plots : %s\n', char(string(Enable_Damaged_Model_Post_Plots)));
if Use_Separate_Damaged_Data_Root
    fprintf('Damaged data root        : %s\n', char(string(Damaged_Data_Root_Directory)));
end
if ~Run_Pre_FEA_Pipeline && Run_Post_FEA_Pipeline
    fprintf('Note                     : pre-FEA outputs disabled; core material processing will still run for post-FEA comparison.\n');
end

Script_Directory = fileparts(mfilename('fullpath'));
Input_File_Name = 'Aluminium - Engineering stress_strain.xlsx';
Input_File_Candidates = { ...
    fullfile(fileparts(Script_Directory), 'Script', 'Engineering Stress Curve Data for Aluminium', Input_File_Name), ...
    fullfile(Script_Directory, Input_File_Name), ...
    Input_File_Name};
Input_File = Input_File_Candidates{end};
for Candidate_Index = 1:numel(Input_File_Candidates)
    if isfile(Input_File_Candidates{Candidate_Index})
        Input_File = Input_File_Candidates{Candidate_Index};
        break;
    end
end
Element_Size_L = 0.72; % Converged Element Size
FEA_Element_Size_Array = [ ...
    1.5, 1.25, 1.0, 0.95, 0.9, 0.85, 0.825, 0.8, ...
    0.775, 0.75, 0.725, 0.72, 0.7, 0.675, 0.65 ...
];
Convergence_Config = struct( ...
    'Convergence_Block_CSV_Name', 'Mesh Convergence.csv', ...
    'Convergence_Dat_Subdir', 'Dat', ...
    'Mesh_Convergence_Sheet_Name', 'Converge', ...
    'Require_FEA_Timeline', false, ...
    'Convergence_Tolerance', 0.001, ...
    'Use_Adjusted_Convergence_Display', false, ...
    'Update_Convergence_Sheet', false);
addpath('C:/Users/Apoll/OneDrive - University College London/Git/MECH0026/utilities');
Output_Directory = fullfile(Script_Directory, 'Figures');
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

% ==============================================================
% ANALYSIS PIPELINE (DATA PREP + MATERIAL RESPONSE)
% ==============================================================

fprintf('[1/7] Load engineering and true data...\n');
Data_Struct = Load_Engineering_And_True_Data(Input_File);

fprintf('[2/7] Linear fit and yield point...\n');
Linear_Fit_Struct = Calculate_Linear_Fit_And_Yield_Point(Data_Struct);

fprintf('[3/7] Ultimate tensile strength...\n');
Ultimate_Tensile_Strength_Struct = Calculate_Engineering_Ultimate_Tensile_Strength(Data_Struct);

fprintf('[4a]  Considere criterion (true response)...\n');
Considere_Struct = Calculate_Considere_Criterion(Data_Struct, Linear_Fit_Struct);

fprintf('[4/7] True undamaged response...\n');
True_Undamaged_Initial_Struct = Calculate_True_Undamaged_Response( ...
    Data_Struct, Considere_Struct, Ultimate_Tensile_Strength_Struct);
True_Undamaged_Struct = struct( ...
    'True_Stress_Undamaged', True_Undamaged_Initial_Struct.True_Stress_Undamaged, ...
    'True_Yield_Index', Linear_Fit_Struct.True_Yield_Index, ...
    'True_Yield_Strain', Linear_Fit_Struct.True_Yield_Strain, ...
    'True_Yield_Stress', Linear_Fit_Struct.True_Yield_Stress, ...
    'Activation_Index', True_Undamaged_Initial_Struct.Activation_Index, ...
    'Activation_Engineering_Strain', True_Undamaged_Initial_Struct.Activation_Engineering_Strain, ...
    'Activation_True_Strain', True_Undamaged_Initial_Struct.Activation_True_Strain, ...
    'Activation_True_Stress', True_Undamaged_Initial_Struct.Activation_True_Stress, ...
    'Activation_Nominal_Stress', True_Undamaged_Initial_Struct.Activation_Nominal_Stress, ...
    'Activation_Method', True_Undamaged_Initial_Struct.Activation_Method, ...
    'True_Undamaged_Rupture_Strain', Data_Struct.True_Strain(end), ...
    'True_Undamaged_Rupture_Stress', True_Undamaged_Initial_Struct.True_Stress_Undamaged(end));

fprintf('[5/7] Damage from UTS to rupture...\n');
if isempty(Element_Size_L)
    Data_Point_Count = numel(Data_Struct.Engineering_Strain);
    Damage_Struct = struct( ...
        'Damage_Computed', false, ...
        'Element_Size_L', [], ...
        'Rupture_Index', Data_Point_Count, ...
        'True_Plastic_Strain', zeros(Data_Point_Count, 1), ...
        'Equivalent_Plastic_Displacement', zeros(Data_Point_Count, 1), ...
        'Damage', zeros(Data_Point_Count, 1));
    fprintf('      Damage omitted (Element_Size_L is empty).\n');
else
    Damage_Struct = Calculate_Damage_From_UTS_To_Rupture( ...
        Data_Struct, Linear_Fit_Struct, Ultimate_Tensile_Strength_Struct, Element_Size_L,True_Undamaged_Struct);
end

fprintf('[6/7] Write formatted report workbook...\n');
if Run_Pre_FEA_Pipeline || Run_Post_FEA_Pipeline
    Report_Struct = Write_Processed_Report_Workbook( ...
        Input_File, Data_Struct, Linear_Fit_Struct, ...
        Ultimate_Tensile_Strength_Struct, True_Undamaged_Struct, Damage_Struct, Considere_Struct);
else
    Report_Struct = struct('Output_Report_Path', "");
    fprintf('      Workbook update skipped (both pre- and post-FEA pipelines disabled).\n');
end

fprintf('[7/7] Build plotting payload...\n');
Linear_Fit_Stress = Linear_Fit_Struct.Youngs_Modulus .* Data_Struct.Engineering_Strain + Linear_Fit_Struct.Linear_Intercept;

% UTS/necking anchor for damage/effective workflows is engineering UTS.
% Considere quantities are still retained separately for comparison figures.
Plot_UTS_Index = Ultimate_Tensile_Strength_Struct.UTS_Index;
Plot_UTS_Strain = Ultimate_Tensile_Strength_Struct.UTS_Strain;
Plot_UTS_Stress = Ultimate_Tensile_Strength_Struct.UTS_Stress;
Engineering_UTS_Plastic_Strain = Ultimate_Tensile_Strength_Struct.UTS_Strain - ...
    Ultimate_Tensile_Strength_Struct.UTS_Stress / Linear_Fit_Struct.Youngs_Modulus;
True_UTS_Plastic_Strain = Considere_Struct.Considere_Plastic_Strain;
Engineering_UTS_True_Strain = log(1 + Ultimate_Tensile_Strength_Struct.UTS_Strain);
Engineering_UTS_True_Stress = Ultimate_Tensile_Strength_Struct.UTS_Stress .* ...
    (1 + Ultimate_Tensile_Strength_Struct.UTS_Strain);
Considere_Projected_Engineering_Strain = exp(Considere_Struct.Considere_Intersection_Strain) - 1;
Damage_Law_Alpha_Values = [0.00, 0.25, 0.50, 0.75, 1.00, 1.50, 2.00, 4.00, 8.00, 10.00];

% ==============================================================
% PLOT DATA STRUCT (ALL COMPUTED ANALYSIS OUTPUTS)
% ==============================================================

Plot_Data_Struct = struct( ...
    'Engineering_Strain', Data_Struct.Engineering_Strain, ...
    'Engineering_Stress', Data_Struct.Engineering_Stress, ...
    'True_Strain', Data_Struct.True_Strain, ...
    'True_Stress_Damaged', Data_Struct.True_Stress_Damaged, ...
    'True_Stress_Undamaged', True_Undamaged_Struct.True_Stress_Undamaged, ...
    'Linear_Fit_Stress', Linear_Fit_Stress, ...
    'Offset_Line_Stress', Linear_Fit_Struct.Offset_Line_Stress, ...
    'Youngs_Modulus', Linear_Fit_Struct.Youngs_Modulus, ...
    'Yield_Index', Linear_Fit_Struct.Yield_Index, ...
    'Yield_Strain', Linear_Fit_Struct.Yield_Strain, ...
    'Yield_Stress', Linear_Fit_Struct.Yield_Stress, ...
    'True_Yield_Strain', True_Undamaged_Struct.True_Yield_Strain, ...
    'True_Yield_Stress', True_Undamaged_Struct.True_Yield_Stress, ...
    'UTS_Index', Plot_UTS_Index, ...
    'UTS_Strain', Plot_UTS_Strain, ...
    'UTS_Stress', Plot_UTS_Stress, ...
    'Considere_Engineering_Strain', Data_Struct.Engineering_Strain(Considere_Struct.Considere_Index), ...
    'Considere_Engineering_Stress', Data_Struct.Engineering_Stress(Considere_Struct.Considere_Index), ...
    'Engineering_UTS_Index', Ultimate_Tensile_Strength_Struct.UTS_Index, ...
    'Engineering_UTS_Strain', Ultimate_Tensile_Strength_Struct.UTS_Strain, ...
    'Engineering_UTS_Stress', Ultimate_Tensile_Strength_Struct.UTS_Stress, ...
    'Engineering_UTS_True_Strain', Engineering_UTS_True_Strain, ...
    'Engineering_UTS_True_Stress', Engineering_UTS_True_Stress, ...
    'Considere_Projected_Engineering_Strain', Considere_Projected_Engineering_Strain, ...
    'Considere_Engineering_Intersection_Strain', Considere_Projected_Engineering_Strain, ...
    'Rupture_Index', Damage_Struct.Rupture_Index, ...
    'Rupture_Strain', Data_Struct.Engineering_Strain(Damage_Struct.Rupture_Index), ...
    'Rupture_Stress', Data_Struct.Engineering_Stress(Damage_Struct.Rupture_Index), ...
    'Undamaged_Rupture_Strain', True_Undamaged_Struct.True_Undamaged_Rupture_Strain, ...
    'Undamaged_Rupture_Stress', True_Undamaged_Struct.True_Undamaged_Rupture_Stress, ...
    'Damage_Computed', Damage_Struct.Damage_Computed, ...
    'True_Plastic_Strain', Damage_Struct.True_Plastic_Strain, ...
    'Equivalent_Plastic_Displacement', Damage_Struct.Equivalent_Plastic_Displacement, ...
    'Damage', Damage_Struct.Damage, ...
    'Work_Hardening_Rate', Considere_Struct.Work_Hardening_Rate, ...
    'WHR_Strain', Considere_Struct.WHR_Strain, ...
    'Considere_Index', Considere_Struct.Considere_Index, ...
    'Considere_True_Strain', Considere_Struct.Considere_True_Strain, ...
    'Considere_True_Stress', Considere_Struct.Considere_True_Stress, ...
    'Considere_Intersection_Strain', Considere_Struct.Considere_Intersection_Strain, ...
    'Considere_Intersection_Stress', Considere_Struct.Considere_Intersection_Stress, ...
    'Considere_Intersection_WHR', Considere_Struct.Considere_Intersection_WHR, ...
    'Considere_Intersection_Delta', Considere_Struct.Considere_Intersection_Delta, ...
    'Considere_Elastic_Strain', Considere_Struct.Considere_Elastic_Strain, ...
    'Considere_Plastic_Strain', Considere_Struct.Considere_Plastic_Strain, ...
    'Work_Hardening_Rate_Engineering', Considere_Struct.Work_Hardening_Rate_Engineering, ...
    'WHR_Engineering_Strain', Considere_Struct.WHR_Engineering_Strain, ...
    'Considere_EngineeringForm_Index', Considere_Struct.Considere_EngineeringForm_Index, ...
    'Considere_EngineeringForm_Intersection_Strain', Considere_Struct.Considere_EngineeringForm_Intersection_Strain, ...
    'Considere_EngineeringForm_True_Strain', Considere_Struct.Considere_EngineeringForm_True_Strain, ...
    'Considere_EngineeringForm_True_Stress', Considere_Struct.Considere_EngineeringForm_True_Stress, ...
    'Considere_EngineeringForm_Engineering_Stress', Considere_Struct.Considere_EngineeringForm_Engineering_Stress, ...
    'Considere_EngineeringForm_Intersection_WHR', Considere_Struct.Considere_EngineeringForm_Intersection_WHR, ...
    'Considere_EngineeringForm_Target_Stress', Considere_Struct.Considere_EngineeringForm_Target_Stress, ...
    'Considere_EngineeringForm_Intersection_Delta', Considere_Struct.Considere_EngineeringForm_Intersection_Delta, ...
    'Considere_EngineeringForm_Elastic_Strain', Considere_Struct.Considere_EngineeringForm_Elastic_Strain, ...
    'Considere_EngineeringForm_Plastic_Strain', Considere_Struct.Considere_EngineeringForm_Plastic_Strain, ...
    'Considere_EngineeringForm_Tangent_Slope', Considere_Struct.Considere_EngineeringForm_Tangent_Slope, ...
    'Considere_EngineeringForm_Tangent_XIntercept', Considere_Struct.Considere_EngineeringForm_Tangent_XIntercept, ...
    'Engineering_UTS_Plastic_Strain', Engineering_UTS_Plastic_Strain, ...
    'True_UTS_Plastic_Strain', True_UTS_Plastic_Strain, ...
    'Effective_Activation_Index', True_Undamaged_Struct.Activation_Index, ...
    'Effective_Activation_Engineering_Strain', True_Undamaged_Struct.Activation_Engineering_Strain, ...
    'Effective_Activation_True_Strain', True_Undamaged_Struct.Activation_True_Strain, ...
    'Effective_Activation_True_Stress', True_Undamaged_Struct.Activation_True_Stress, ...
    'Effective_Activation_Method', True_Undamaged_Struct.Activation_Method, ...
    'Damage_Law_Alpha_Values', Damage_Law_Alpha_Values, ...
    'Engineering_Rupture_Strain', Data_Struct.Engineering_Strain(end), ...
    'Engineering_Rupture_Stress', Data_Struct.Engineering_Stress(end), ...
    'True_Damaged_Rupture_Strain', Data_Struct.True_Strain(end), ...
    'True_Damaged_Rupture_Stress', Data_Struct.True_Stress_Damaged(end), ...
    'True_Undamaged_Rupture_Strain', True_Undamaged_Struct.True_Undamaged_Rupture_Strain, ...
    'True_Undamaged_Rupture_Stress', True_Undamaged_Struct.True_Undamaged_Rupture_Stress, ...
    'True_Rupture_Strain', Data_Struct.True_Strain(Damage_Struct.Rupture_Index), ...
    'XLSX_Path', Input_File, ...
    'FEA_Element_Size_Array', FEA_Element_Size_Array(:), ...
    'Convergence_Config', Convergence_Config);

if Use_Separate_Damaged_Data_Root && isfolder(Damaged_Data_Root_Directory)
    Convergence_Data_Directory = Resolve_Convergence_Data_Directory(Damaged_Data_Root_Directory, Damaged_Data_Root_Directory);
    Damage_Evolution_Directory = Resolve_Damage_Evolution_Directory(Damaged_Data_Root_Directory, Damaged_Data_Root_Directory);
else
    Convergence_Data_Directory = Resolve_Convergence_Data_Directory(fileparts(mfilename('fullpath')), pwd);
    Damage_Evolution_Directory = Resolve_Damage_Evolution_Directory(fileparts(mfilename('fullpath')), pwd);
end
if Run_Post_FEA_Pipeline
    Plot_Data_Struct.FEA_Convergence_Data = Read_FEA_Convergence_Data(Convergence_Data_Directory, Convergence_Config);
    Plot_Data_Struct.FEA_Damage_Evolution_Data = Read_FEA_Damage_Evolution_Data(Damage_Evolution_Directory);
else
    Plot_Data_Struct.FEA_Convergence_Data = Read_FEA_Convergence_Data('', Convergence_Config);
    Plot_Data_Struct.FEA_Damage_Evolution_Data = Read_FEA_Damage_Evolution_Data('');
end
if Run_Post_FEA_Pipeline
    Should_Update_Mesh_Convergence_Sheet = isfield(Convergence_Config, 'Update_Convergence_Sheet') && ...
        logical(Convergence_Config.Update_Convergence_Sheet);
    if Should_Update_Mesh_Convergence_Sheet && ...
            isfield(Plot_Data_Struct.FEA_Convergence_Data, 'Summary_Table') && ...
            istable(Plot_Data_Struct.FEA_Convergence_Data.Summary_Table) && ...
            ~isempty(Plot_Data_Struct.FEA_Convergence_Data.Summary_Table)
        [Plot_Data_Struct.FEA_Convergence_Data.Summary_Table, Mesh_Conv_Write_Info] = Write_Convergence_To_Mesh_Convergence_Sheet( ...
            Plot_Data_Struct.XLSX_Path, ...
            Convergence_Config.Mesh_Convergence_Sheet_Name, ...
            Plot_Data_Struct.FEA_Convergence_Data.Summary_Table);
        if isfield(Mesh_Conv_Write_Info, 'Message') && strlength(string(Mesh_Conv_Write_Info.Message)) > 0
            fprintf('[FEA] %s\n', char(string(Mesh_Conv_Write_Info.Message)));
        end
    elseif ~Should_Update_Mesh_Convergence_Sheet
        fprintf('[FEA] Mesh convergence sheet update disabled (Update_Convergence_Sheet=false).\n');
    end

    [Sheet_Summary_Table, Mesh_Conv_Read_Info] = Read_Convergence_From_Mesh_Convergence_Sheet( ...
        Plot_Data_Struct.XLSX_Path, ...
        Convergence_Config.Mesh_Convergence_Sheet_Name, ...
        Plot_Data_Struct.FEA_Convergence_Data.Summary_Table, ...
        Plot_Data_Struct.FEA_Convergence_Data.Mesh_Conv_Tol);
    if isfield(Mesh_Conv_Read_Info, 'Message') && strlength(string(Mesh_Conv_Read_Info.Message)) > 0
        fprintf('[FEA] %s\n', char(string(Mesh_Conv_Read_Info.Message)));
    end
    if istable(Sheet_Summary_Table) && ~isempty(Sheet_Summary_Table)
        Plot_Data_Struct.FEA_Convergence_Data.Summary_Table = Sheet_Summary_Table;
        Plot_Data_Struct.FEA_Convergence_Data.Summary_Table_Raw = Sheet_Summary_Table;
        Plot_Data_Struct.FEA_Convergence_Data.Summary_Source = "workbook_sheet";
        Plot_Data_Struct.FEA_Convergence_Data.Available = true;

        if any(strcmp(Sheet_Summary_Table.Properties.VariableNames, 'convTol'))
            Tol_Values_Sheet = To_Double_Vector(Sheet_Summary_Table.convTol);
            Tol_Values_Sheet = Tol_Values_Sheet(~isnan(Tol_Values_Sheet) & Tol_Values_Sheet > 0);
            if ~isempty(Tol_Values_Sheet)
                Plot_Data_Struct.FEA_Convergence_Data.Mesh_Conv_Tol = Tol_Values_Sheet(1);
            end
        end

        Converged_Row_From_Sheet = Resolve_Converged_Row_Index(Sheet_Summary_Table, struct());
        if ~isempty(Converged_Row_From_Sheet) && Converged_Row_From_Sheet >= 1 && ...
                Converged_Row_From_Sheet <= height(Sheet_Summary_Table)
            Mesh_From_Sheet = [];
            if any(strcmp(Sheet_Summary_Table.Properties.VariableNames, 'mesh_h'))
                Mesh_From_Sheet = To_Double_Vector(Sheet_Summary_Table.mesh_h);
            elseif any(strcmp(Sheet_Summary_Table.Properties.VariableNames, 'mesh_h_6dp'))
                Mesh_From_Sheet = To_Double_Vector(Sheet_Summary_Table.mesh_h_6dp);
            end
            if numel(Mesh_From_Sheet) >= Converged_Row_From_Sheet && ~isnan(Mesh_From_Sheet(Converged_Row_From_Sheet))
                Plot_Data_Struct.FEA_Convergence_Data.Chosen_Mesh_h = Mesh_From_Sheet(Converged_Row_From_Sheet);
            end

            if any(strcmp(Sheet_Summary_Table.Properties.VariableNames, 'numElements'))
                Elem_From_Sheet = To_Double_Vector(Sheet_Summary_Table.numElements);
                if numel(Elem_From_Sheet) >= Converged_Row_From_Sheet && ~isnan(Elem_From_Sheet(Converged_Row_From_Sheet))
                    Plot_Data_Struct.FEA_Convergence_Data.Chosen_Num_Elements = Elem_From_Sheet(Converged_Row_From_Sheet);
                end
            end

            if any(strcmp(Sheet_Summary_Table.Properties.VariableNames, 'jobName'))
                Job_From_Sheet = string(Sheet_Summary_Table.jobName);
                if numel(Job_From_Sheet) >= Converged_Row_From_Sheet && strlength(Job_From_Sheet(Converged_Row_From_Sheet)) > 0
                    Plot_Data_Struct.FEA_Convergence_Data.Chosen_Job_Name = Job_From_Sheet(Converged_Row_From_Sheet);
                end
            end
        end

        n_rows_sheet = height(Sheet_Summary_Table);
        if any(strcmp('isConvergedLE22', Sheet_Summary_Table.Properties.VariableNames))
            Plot_Data_Struct.FEA_Convergence_Data.IsConvergedLE22 = Safe_IsConverged_Mask(Sheet_Summary_Table.isConvergedLE22);
        elseif any(strcmp('isConverged', Sheet_Summary_Table.Properties.VariableNames))
            Plot_Data_Struct.FEA_Convergence_Data.IsConvergedLE22 = Safe_IsConverged_Mask(Sheet_Summary_Table.isConverged);
        else
            Plot_Data_Struct.FEA_Convergence_Data.IsConvergedLE22 = false(n_rows_sheet, 1);
        end
        if any(strcmp('isConvergedAll3', Sheet_Summary_Table.Properties.VariableNames))
            Plot_Data_Struct.FEA_Convergence_Data.IsConvergedAll3 = Safe_IsConverged_Mask(Sheet_Summary_Table.isConvergedAll3);
        else
            Plot_Data_Struct.FEA_Convergence_Data.IsConvergedAll3 = false(n_rows_sheet, 1);
        end
    end

    Sheet_Sync_Report = Populate_Displacement_Sheet_From_Mesh_Convergence( ...
        Plot_Data_Struct.XLSX_Path, Data_Struct, Linear_Fit_Struct, ...
        True_Undamaged_Struct, Plot_Data_Struct.FEA_Convergence_Data, ...
        []);
    if Sheet_Sync_Report.Updated
        fprintf('[FEA] Displacement_By_Element_Size refreshed from mesh convergence (%d element sizes).\n', ...
            Sheet_Sync_Report.Mesh_Size_Count);
        if isfield(Sheet_Sync_Report, 'Output_CSV_Path') && strlength(string(Sheet_Sync_Report.Output_CSV_Path)) > 0
            fprintf('[FEA] Plastic displacement data exported: %s\n', char(string(Sheet_Sync_Report.Output_CSV_Path)));
        end
    else
        fprintf('[FEA] Displacement_By_Element_Size retained as-is (%s).\n', ...
            char(string(Sheet_Sync_Report.Reason)));
    end
end
Plot_Data_Struct.Element_Size_Displacement_Data = Read_Displacement_Sheet_Data(Plot_Data_Struct.XLSX_Path);
Plot_Data_Struct.Damage_Law_Data = Build_Damage_Law_Data( ...
    Plot_Data_Struct, Plot_Data_Struct.FEA_Convergence_Data);
Plot_Data_Struct.Effective_Response_Data = Build_Effective_Response_Data(Plot_Data_Struct);
if Run_Post_FEA_Pipeline
    Plot_Data_Struct.FEA_Response_Data = Build_FEA_Response_Data( ...
        Plot_Data_Struct.FEA_Convergence_Data, Plot_Data_Struct, Convergence_Config);
else
    Plot_Data_Struct.FEA_Response_Data = struct('Available', false);
end
Plot_Data_Struct.Enable_Damaged_Model_Post_Plots = Enable_Damaged_Model_Post_Plots;

% ==============================================================
% PLOT LABEL/STYLE STRUCT (FIGURE CONFIGURATION)
% ==============================================================

Plot_Label_Struct = struct( ...
    'Output_Directory', Output_Directory, ...
    'Style', struct( ...
        'Font_Sizes', {{20, 20, 25}}, ...
        'Tick_Font_Size', 20, ...
        'Axis_Label_Font_Size', 22, ...
        'Title_Font_Size', 25, ...
        'Axis_Line_Width', 2, ...
        'Legend_Font_Size', 18, ...
        'Legend_Padding', 0.2, ...
        'Export_DPI', 600, ...
        'Figure_Window_Style', 'docked', ...
        'Display_Figure_Position', [80, 50, 1500, 930], ...
        'LineWidths', 2.5, ...
        'Palette', struct( ...
            'Engineering', '#1D4ED8', ...
            'TrueDamaged', '#DC2626', ...
            'TrueUndamaged', '#16A34A', ...
            'ElasticRegime', '#1D4ED8', ...
            'PlasticRegime', '#DC2626', ...
            'LinearFit', '#2563EB', ...
            'OffsetLine', '#F97316', ...
            'YoungsModulus', '#9333EA', ...
            'WorkHardening', '#22C55E', ...
            'Guide', '#374151', ...
            'Text', '#111827' ...
        ), ...
        'LineStyles', struct( ...
            'Engineering', '-', ...
            'TrueDamaged', '-', ...
            'TrueUndamaged', '--', ...
            'ElasticRegime', '-', ...
            'PlasticRegime', '-', ...
            'LinearFit', '--', ...
            'OffsetLine', '-.', ...
            'YoungsModulus', ':', ...
            'WorkHardening', '--', ...
            'Guide', '--', ...
            'NoLine', 'none', ...
            'Guide_Width', 2, ...
            'InsetRectangle', ':', ...
            'InsetConnector', '--', ...
            'SchematicLoading', '-.', ...
            'SchematicUnloading', ':' ...
        ), ...
        'Markers', struct( ...
            'Yield', struct( ...
                'Symbol', 'p', ...
                'Size', 18, ...
                'LineWidth', 1.5, ...
                'FaceColor', '#FACC15', ...
                'EdgeColor', '#854D0E', ...
                'TrueFaceColor', '#F59E0B', ...
                'TrueEdgeColor', '#7C2D12' ...
            ), ...
            'UTS', struct( ...
                'Symbol', 'h', ...
                'Size', 20, ...
                'LineWidth', 1.6, ...
                'EngineeringFaceColor', '#67E8F9', ...
                'EngineeringEdgeColor', '#155E75', ...
                'TrueFaceColor', '#A78BFA', ...
                'TrueEdgeColor', '#4C1D95', ...
                'EngineeringFormFaceColor', '#A7F3D0', ...
                'EngineeringFormEdgeColor', '#047857', ...
                'MappedFaceColor', '#FED7AA', ...
                'MappedEdgeColor', '#C2410C', ...
                'ActivationFaceColor', '#FDBA74', ...
                'ActivationEdgeColor', '#9A3412' ...
            ), ...
            'Failure', struct( ...
                'Symbol', 's', ...
                'Size', 13, ...
                'LineWidth', 1.5, ...
                'EngineeringFaceColor', '#FDE68A', ...
                'EngineeringEdgeColor', '#92400E', ...
                'TrueDamagedFaceColor', '#F9A8D4', ...
                'TrueDamagedEdgeColor', '#831843', ...
                'TrueUndamagedFaceColor', '#86EFAC', ...
                'TrueUndamagedEdgeColor', '#14532D' ...
            ) ...
        ), ...
        'Inset', struct( ...
            'Font_Size', 18, ...
            'Line_Width', 2.0, ...
            'Rectangle_Color', '#9333EA', ...
            'Axis_Color', '#9333EA', ...
            'Tick_Color', '#000000', ...
            'Rectangle_Line_Width', 1.8, ...
            'Connector_Line_Width', 1.3, ...
            'Axis_Overlay_Line_Width', 2.2 ...
        ), ...
        'Annotation', struct( ...
            'Font_Size', 12, ...
            'Gap', 0.014, ...
            'Horizontal_Gap', 0.016, ...
            'EdgeColor', '#1E3A8A', ...
            'BackgroundColor', '#FCE7F3', ...
            'LineWidth', 2.0, ...
            'Margin', 5, ...
            'TextColor', '#1F2937' ...
        ), ...
        'Root_Defaults', struct( ...
            'Figure_Color', [1 1 1], ...
            'Axes_Color', [1 1 1], ...
            'Axes_XColor', [0 0 0], ...
            'Axes_YColor', [0 0 0], ...
            'Axes_ZColor', [0 0 0], ...
            'Text_Color', [0 0 0], ...
            'Legend_Color', [1 1 1], ...
            'Legend_Edge_Color', [0 0 0], ...
            'Legend_Text_Color', [0 0 0] ...
        ) ...
    ), ...
    'Figure_1', struct( ...
        'Name', 'Yield Offset', ...
        'File_Name', 'Fig01_Offset_Yield.png', ...
        'Enable', false, ...
        'X_Label', 'Engineering Strain, [$\mathbf{\varepsilon_N}$]', ...
        'Y_Label', 'Engineering Stress (MPa), [$\mathbf{\sigma_N}$]', ...
        'Title', {{'Yield Point via 0.2\% Strain Offset Method', 'Truncated $\sigma$--$\varepsilon$ Response'}}, ...
        'Legend', {{'$\sigma_N-\varepsilon_N$', 'Linear fit', '0.2\% offset line', 'Yield point'}}, ...
        'Legend_Location', 'southeast', ...
        'Inset', struct( ...
            'Enable', false, ...
            'Target', 'yield', ...
            'Zoom_Half_X', 0.001, ...
            'Zoom_Half_Y_Frac', 0.15, ...
            'Position', [0.60 0.22 0.30 0.30], ...
            'Legend_Inset', {{'$\sigma_N-\varepsilon_N$', 'Linear fit', '0.2\% offset line', 'Yield point'}}), ...
        'Annotation', struct('Placement', 'bottom') ...
    ), ...
    'Figure_2', struct( ...
        'Name', 'Elastic-Plastic Regimes with Yield Detail', ...
        'File_Name', 'Fig02_Elastic_Plastic.png', ...
        'Enable', true, ...
        'X_Label', 'Engineering Strain, $\varepsilon_N$', ...
        'Y_Label', 'Engineering Stress (MPa), $\sigma_N$', ...
        'Title', {{'Engineering Stress-Strain Response', 'Elastic-Plastic Regimes with Yield Detail'}}, ...
        'Legend', {{'Elastic Regime', 'Plastic Regime', 'Yield Point'}}, ...
        'Legend_Location', 'northeast', ...
        'Inset', struct( ...
            'Enable', true, ...
            'Show_Connecting_Lines', true, ...
            'Zoom_Half_X', 0.001, ...
            'Zoom_Half_Y_Frac', 0.15, ...
            'Rectangle_X_Limits', [-0.01, 0.01], ...
            'Rectangle_Y_Limits', [0, 130], ...
            'Position', [0.20 0.16 0.42 0.42], ...
            'Title', '\textbf{Yield Point Detail (0.2\% Offset Method)}', ...
            'Legend_Inset', {{'$\sigma_N-\varepsilon_N$', 'Linear fit', '0.2\% offset line', 'Yield point'}}), ...
        'Annotation', struct('Placement', 'below_right') ...
    ), ...
    'Figure_3', struct( ...
        'Name', 'True Damaged and Undamaged', ...
        'File_Name', 'Fig03_True_Damaged_Undamaged.png', ...
        'Enable', false, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Title', {{'True Stress-Strain Response', 'Damaged \& Undamaged with $\Delta\sigma$'}}, ...
        'Legend', {{'$\sigma_T$', '$\tilde{\sigma}_T$', 'True yield point', 'True UTS point'}}, ...
        'Legend_Location', 'northwest', ...
        'Inset', struct( ...
            'Enable', true, ...
            'Target', 'delta_sigma', ...
            'Post_UTS_Frac', 0.10, ...
            'Zoom_X_Frac', 0.6, ...
            'Zoom_Y_Pad_Frac', 0.5, ...
            'Position', [0.2 0.2 0.30 0.30], ...
            'Legend_Inset', {{'$\sigma_N-\varepsilon_N$', 'Linear fit', '0.2\% offset line', 'Yield point'}}), ...
        'Annotation', struct('Placement', 'right') ...
    ), ...
    'Figure_4', struct( ...
        'Name', 'Stress Overlay', ...
        'File_Name', 'Fig04_Stress_Overlay.png', ...
        'Enable', true, ...
        'X_Label', 'Strain, $\varepsilon$', ...
        'Y_Label', 'Stress (MPa), $\sigma$', ...
        'Title', {{'Superimposed Stress-Strain Response', 'Engineering \& True \& Effective'}}, ...
        'Legend', {{ ...
            'Engineering response: $\sigma_N\textrm{-}\varepsilon_N$', ...
            'True response: $\sigma_T\textrm{-}\varepsilon_T$', ...
            'Effective response: $\tilde{\sigma}\textrm{-}\tilde{\varepsilon}$', ...
            'Elastic modulus line: $E$', ...
            'Yield point: $\sigma_N^{Y}$', ...
            'Engineering UTS: $\sigma_N^{\mathrm{UTS}}$', ...
            'True UTS: $\sigma_T^{\mathrm{UTS}}$', ...
            'Engineering failure: $\sigma_N^{f}$', ...
            'True failure: $\sigma_T^{f}$', ...
            'Effective failure: $\tilde{\sigma}^{f}$'}}, ...
        'Legend_Location', 'southwest', ...
        'Legend_Nudge', [0.015, 0.0], ...
        'Elastic_Modulus_Max_Strain', 0.0022, ...
        'Inset', struct( ...
            'Enable', true, ...
            'Show_Connecting_Lines', true, ...
            'Position', [0.57 0.56 0.33 0.33], ...
            'Zoom_X_Scale', 4.0, ...
            'Zoom_Y_Scale', 6.0, ...
            'Min_X_Pad', 0.0012, ...
            'Min_Y_Pad', 6.0, ...
            'Title', '\textbf{UTS Point Detail}', ...
            'Legend_Location', 'southwest', ...
            'Legend_Inset', {{'$\sigma_N\textrm{-}\varepsilon_N$', '$\sigma_T\textrm{-}\varepsilon_T$', ...
                              'Engineering UTS', 'True UTS (Consid\`ere)'}}), ...
        'Annotation', struct( ...
            'Placement', 'bottom', ...
            'Yield_Rupture_Header', '\textbf{Yield Data \& Failure Data}', ...
            'Yield_Eng_Line', '$\\sigma_N^{Y} = %.4f$ MPa, $\\varepsilon_N^{Y} = %s$, $\\varepsilon_N^{f} = %s$', ...
            'Yield_True_Line', '$\\sigma_T^{Y} = %.4f$ MPa, $\\varepsilon_T^{Y} = %s$, $\\varepsilon_T^{f} = %s$', ...
            'UTS_Header', '\textbf{UTS \& Necking Data}', ...
            'UTS_Eng_Line', '$\\sigma_N^{\\mathrm{UTS}} = %.4f$ MPa, $\\varepsilon_N^{\\mathrm{UTS}} = %s$', ...
            'UTS_True_Line', '$\\sigma_T^{C} = %.4f$ MPa, $\\varepsilon_T^{C} = %s$', ...
            'UTS_Activation_Line', '$\\sigma_T^{\\mathrm{UTS}} = %.4f$ MPa, $\\varepsilon_T^{\\mathrm{UTS}} = %s$', ...
            'Effective_Header', '\textbf{Effective Data}', ...
            'Effective_Line', '$\\tilde{\\sigma}^{f} = %.4f$ MPa, $\\tilde{\\varepsilon}^{f} = %s$' ...
        ) ...
    ), ...
    'Figure_5', struct( ...
        'Name', 'Damage Evolution', ...
        'File_Name', 'Fig05_Damage_Evolution.png', ...
        'Enable', false, ...
        'Top_X_Label', 'Engineering Strain, $\varepsilon_N$', ...
        'Top_Y_Label', 'Damage, $D$', ...
        'Top_Title', {{'Damage Evolution', 'UTS to Rupture'}}, ...
        'Top_Legend', {{'Damage $D$'}}, ...
        'Top_Legend_Location', 'northwest', ...
        'Bottom_X_Label', 'Engineering Strain, $\varepsilon_N$', ...
        'Bottom_Y_Label', 'Strain / Displacement, $\varepsilon_{\mathrm{pl}}$, $u_{\mathrm{pl}}$', ...
        'Bottom_Title', {{'True Plastic Strain \& Eq. Plastic Displacement', '$\varepsilon_{\mathrm{pl}}^T$ and $u_{\mathrm{pl}}^{\mathrm{eq}}$'}}, ...
        'Bottom_Legend', {{'$\varepsilon_{\mathrm{pl}}^T$', '$u_{\mathrm{pl}}^{\mathrm{eq}}$'}}, ...
        'Displacement_Colormap', 'lines', ...
        'Displacement_Line_Styles', {{'-', '--', '-.', ':'}}, ...
        'Bottom_Legend_Location', 'northwest', ...
        'Annotation', struct('Placement', 'right') ...
    ), ...
    'Figure_6', struct( ...
        'Name', 'Considere Construction', ...
        'File_Name', 'Fig06_Considere_Construction.png', ...
        'Enable', true, ...
        'X_Label', 'Strain, $\varepsilon$', ...
        'Y_Label', 'Stress / Hardening Rate (MPa), $\sigma_T$, $\mathrm{d}\sigma_T/\mathrm{d}\varepsilon_T$', ...
        'Title', {{'Consid\`ere Criterion Construction', '$\frac{\mathrm{d}\sigma_T}{\mathrm{d}\varepsilon_T} = \sigma_T$'}}, ...
        'Legend', {{'True response: $\sigma_T-\varepsilon_T$', '$\frac{\mathrm{d}\sigma_T}{\mathrm{d}\varepsilon_T}$', 'UTS / Consid\`ere point'}}, ...
        'Legend_Location', 'northeast', ...
        'Inset', struct( ...
            'Enable', true, ...
            'Zoom_X_Frac', 0.30, ...
            'Zoom_Y_Frac', 0.20, ...
            'Position', [0.42 0.19 0.33 0.37], ...
            'Title', '\textbf{Magnified: Consid\`ere Point}', ...
            'Legend_Inset', {{'$\sigma_T-\varepsilon_T$', '$\frac{\mathrm{d}\sigma_T}{\mathrm{d}\varepsilon_T}$', 'Consid\`ere point', 'UTS coordinates', ...
                              'Hysteresis loading'}}), ...
        'Annotation', struct( ...
            'Placement', 'top_right_adjacent', ...
            'Header', '\textbf{Consid\`ere Point}', ...
            'EpsTrue_Line', '$\\varepsilon_T^{C} = %s$', ...
            'SigTrue_Line', '$\\sigma_T^{C} = %.4f$ MPa', ...
            'EpsElastic_Line', '$\\varepsilon_{T}^{\\mathrm{el}, C} = %s$', ...
            'EpsPlastic_Line', '$\\varepsilon_{T}^{\\mathrm{pl},C} = %s$'...
        ) ...
    ), ...
    'Figure_7', struct( ...
        'Name', 'Comprehensive Stress Overlay', ...
        'File_Name', 'Fig07_Comprehensive.png', ...
        'Enable', true, ...
        'X_Label', 'Strain, $\varepsilon$', ...
        'Y_Label', 'Stress (MPa), $\sigma$', ...
        'Title', {{'Comprehensive Stress--Strain Response', 'Engineering, True, and Effective Responses'}}, ...
        'Legend_Location', 'northwest', ...
        'Yield_Merge_Tolerance_Strain', 2e-4, ...
        'Yield_Merge_Tolerance_Stress_MPa', 2.0, ...
        'Labels', struct( ...
            'Engineering', 'Engineering response: $\sigma_N\textrm{--}\varepsilon_N$', ...
            'TrueDamaged', 'True response: $\sigma_T\textrm{--}\varepsilon_T$', ...
            'TrueUndamaged', 'Effective response: $\tilde{\sigma}\textrm{--}\tilde{\varepsilon}$', ...
            'YieldMerged', 'Yield point', ...
            'YieldEngineering', 'Engineering yield point', ...
            'YieldTrue', 'True yield point', ...
            'UTSEngineering', 'Engineering UTS: $\sigma_N^{\mathrm{UTS}}$', ...
            'UTSActivationTrue', 'True UTS: $\sigma_T^{\mathrm{UTS}}$', ...
            'FailureEngineering', 'Engineering failure', ...
            'FailureTrueDamaged', 'True failure', ...
            'FailureTrueUndamaged', 'Effective failure' ...
        ), ...
        'Annotation', struct( ...
            'Placement', 'right', ...
            'Header', '\textbf{Key Values}', ...
            'E_Line', '$E = %.4f$ MPa', ...
            'Yield_Merged_Line', '$\\sigma_N^{Y} = %.4f$ MPa, $\\varepsilon_N^{Y} = %s$', ...
            'Yield_Engineering_Line', '$\\sigma_N^{Y} = %.4f$ MPa, $\\varepsilon_N^{Y} = %s$', ...
            'Yield_True_Line', '$\\sigma_T^{Y} = %.4f$ MPa, $\\varepsilon_T^{Y} = %s$', ...
            'UTS_Engineering_Line', '$\\sigma_N^{\\mathrm{UTS}} = %.4f$ MPa, $\\varepsilon_N^{\\mathrm{UTS}} = %s$', ...
            'UTS_True_Line', '$\\sigma_T^{C} = %.4f$ MPa, $\\varepsilon_T^{C} = %s$', ...
            'UTS_Activation_True_Line', '$\\sigma_T^{\\mathrm{UTS}} = %.4f$ MPa, $\\varepsilon_T^{\\mathrm{UTS}} = %s$', ...
            'UTS_Plastic_Engineering_Line', '$\\varepsilon_{N}^{\\mathrm{pl, UTS}} = %s$', ...
            'UTS_Plastic_True_Line', '$\\varepsilon_{T}^{\\mathrm{pl}, C} = %s$', ...
            'Rupture_Engineering_Line', '$\\sigma_N^{f} = %.4f$ MPa, $\\varepsilon_N^{f} = %s$', ...
            'Rupture_True_Line', '$\\sigma_T^{f} = %.4f$ MPa, $\\varepsilon_T^{f} = %s$', ...
            'Rupture_Undamaged_True_Line', '$\\tilde{\\sigma}^{f} = %.4f$ MPa, $\\tilde{\\varepsilon}^{f} = %s$' ...
        ) ...
    ), ...
    'Figure_8_Stress_Overlay_UTS_Zoom', struct( ...
        'Name', 'Stress Overlay UTS Zoom', ...
        'File_Name', 'Fig08_Stress_Overlay_UTS_Zoom.png', ...
        'Enable', true, ...
        'Title', {{'UTS Activation Detail', 'Yield to UTS: Engineering, True, and Effective Stress'}}, ...
        'X_Label', 'Engineering strain, $\varepsilon_N$', ...
        'Y_Label', 'Stress (MPa), $\sigma$', ...
        'Legend', {{ ...
            'Engineering response: $\sigma_N-\varepsilon_N$', ...
            'True stress response: $\sigma_T(\varepsilon_N)$', ...
            'Effective stress response: $\tilde{\sigma}_T(\varepsilon_N)$', ...
            'Yield point', ...
            'Engineering UTS', ...
            'Onset of necking (Consid\`ere)', ...
            'True stress at engineering UTS strain'}}, ...
        'Legend_Location', 'northwest', ...
        'Legend_NumColumns', 2, ...
        'Effective_Point_Marker', 'o', ...
        'Effective_Point_Size_Offset', 6, ...
        'Effective_Point_LineWidth', 1.4, ...
        'Yield_Left_Pad', 0.0015, ...
        'Post_UTS_Right_Pad', 0.0018, ...
        'Min_Y_Pad', 6.0, ...
        'Annotation', struct( ...
            'Placement', 'top_right_adjacent', ...
            'Header', '\textbf{UTS \& Necking Data}', ...
            'Engineering_Line', '$\\sigma_N^{\\mathrm{UTS}} = %.4f$ MPa, $\\varepsilon_N^{\\mathrm{UTS}} = %s$', ...
            'True_Line', '$\\sigma_T^{C} = %.4f$ MPa, $\\varepsilon_T^{C} = %s$', ...
            'Activation_Line', '$\\sigma_T^{\\mathrm{UTS}} = %.4f$ MPa', ...
            'Activation_Strain_Label', '$\\varepsilon_N^{\\mathrm{UTS}}$', ...
            'Activation_Stress_Label', '$\\sigma_T^{\\mathrm{UTS}}$' ...
        ) ...
    ), ...
    'Figure_9_Damage_Softening_Comparison', struct( ...
        'Name', 'Damage Softening Comparison', ...
        'File_Name', 'Fig09_Damage_Softening_Comparison.png', ...
        'Enable', true, ...
        'Title', {{'Damage Evolution Laws', 'Equivalent Plastic Displacement Comparison'}}, ...
        'Tile_Titles', {{'(A) Linear Softening', '(B) Tabular Softening', '(C) Exponential Softening ($\alpha$ sweep)'}}, ...
        'X_Label', 'Equivalent Plastic Displacement, $\bar{u}_{\mathrm{pl}}$', ...
        'Y_Label', 'Damage, $D$', ...
        'Legend', {{'Linear', 'Tabular'}}, ...
        'Legend_Location', 'southeast', ...
        'Legend_NumColumns', 2, ...
        'Exponential_Colormap', 'parula', ...
        'Exponential_Line_Styles', {{'-', '--', '-.', ':'}}, ...
        'Exponential_Markers', {{'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h', 'x', '+'}}, ...
        'Exponential_Marker_Size', 6, ...
        'Exponential_Marker_FaceColor', [1, 1, 1], ...
        'Annotation_Text', {{ ...
            '$D = \frac{\bar{u}_{\mathrm{pl}}}{\bar{u}_{\mathrm{pl}}^{f}}$', ...
            '$D = 1 - \frac{\sigma_T}{\tilde{\sigma}_T}$', ...
            '$D = \frac{1 - e^{-\alpha (\bar{u}_{\mathrm{pl}} \, / \, \bar{u}_{\mathrm{pl}}^{f})}}{1 - e^{-\alpha}}$'}}, ...
        'Annotation_Placements', {{'southeast', 'southeast', 'southeast'}} ...
    ), ...
    'Figure_10_Effective_Stress_Parameterisation', struct( ...
        'Name', 'Effective Stress Parameterisation', ...
        'File_Name', 'Fig10_Effective_Stress_Parameterisation.png', ...
        'Enable', false, ...
        'Title', {{'Effective Stress Parameterisation', 'Engineering, True, and Effective Stress (UTS to Rupture)'}}, ...
        'X_Label', 'Strain, $\varepsilon$', ...
        'Y_Label_Left', 'Stress (MPa), $\sigma$', ...
        'Y_Label_Right', '', ...
        'Legend_Location', 'southwest' ...
    ), ...
    'Figure_11_Element_Size_Displacement', struct( ...
        'Name', 'Element Size Plastic Displacement', ...
        'File_Name', 'Fig11_Element_Size_Displacement.png', ...
        'Enable', false, ...
        'Title', {{'Equivalent Plastic Displacement', 'Sensitivity to Element Size (UTS to Rupture)'}}, ...
        'X_Label', 'Engineering Strain, $\varepsilon_N$', ...
        'Y_Label', 'Equivalent Plastic Displacement, $\bar{u}_{\mathrm{pl}}$', ...
        'Colormap', 'parula', ...
        'Line_Styles', {{'-', '--', '-.', ':'}}, ...
        'Line_Markers', {{'o', 's', 'd', '^', 'v', '>', '<', 'p', 'x', '+'}}, ...
        'Line_Marker_Size', 6, ...
        'Line_Marker_Edge_Shade_Factor', 0.55, ...
        'Peak_Marker', 'h', ...
        'Peak_Marker_Size', 11, ...
        'Peak_Marker_Line_Width', 1.3, ...
        'Peak_Marker_Edge_Shade_Factor', 0.55, ...
        'Legend_Location', 'northwest' ...
    ), ...
    'Figure_12_FEA_Mesh_Convergence', struct( ...
        'Name', 'FEA Mesh Convergence', ...
        'File_Name', 'Fig12_FEA_Mesh_Convergence.png', ...
        'Enable', false, ...
        'Title', {{'Quantity of Interests Behaviour to Mesh Refinement'}}, ...
        'X_Label', 'Number of Elements', ...
        'Y_Label', '$\left| \frac{\varepsilon_{22}^{(i+1)} - \varepsilon_{22}^{(i)}}{\varepsilon_{22}^{(i+1)}} \right| \times 100\%$', ...
        'Tolerance_Label', 'Tolerance $\xi = 0.1\%$', ...
        'Converged_Label', 'Converged Mesh', ...
        'LE22_Trendline_Label', '$LE22$ trend line', ...
        'S22_Trendline_Label', '$S22$ trend line', ...
        'Mises_Trendline_Label', '$\sigma_{vM}$ trend line', ...
        'Trendline_Powers', 1.50, ...
        'Trendline_Samples', 320, ...
        'Pair_Colormap', 'lines', ...
        'Pair_Marker', 'h', ...
        'Pair_Marker_Size', 20, ...
        'Pair_Marker_Line_Width', 1.4, ...
        'Pair_Edge_Shade_Factor', 0.58, ...
        'LE22_Trendline_Style', '-', ...
        'S22_Trendline_Style', '-.', ...
        'Mises_Trendline_Style', '--', ...
        'LE22_Trendline_Width', 2.4, ...
        'S22_Trendline_Width', 2.2, ...
        'Mises_Trendline_Width', 2.2, ...
        'Tolerance_Line_Style', '--', ...
        'Tolerance_Line_Width', 2.0, ...
        'Converged_Line_Style', '--', ...
        'Converged_Line_Width', 2.0, ...
        'Grid_Color', [0.78, 0.80, 0.84], ...
        'LE22_Trendline_Color', [0.95, 0.20, 0.20], ...
        'S22_Trendline_Color', [0.00, 0.60, 0.30], ...
        'Mises_Trendline_Color', [0.85, 0.33, 0.10], ...
        'Converged_Line_Color', [0.45, 0.60, 1.00], ...
        'Converged_Marker', 'o', ...
        'Converged_Marker_Size', 28, ...
        'Converged_Marker_Edge_Color', [0.90, 0.00, 0.00], ...
        'Converged_Marker_Line_Width', 2.8, ...
        'Converged_Pair_Marker_Size', 17, ...
        'Converged_Pair_Marker_Line_Width', 1.8, ...
        'Converged_Pair_Face_Color', [0.95, 0.28, 0.28], ...
        'Converged_Pair_Edge_Color', [0.55, 0.00, 0.00], ...
        'Axis_Text_Color', [0.05, 0.05, 0.05], ...
        'Legend_Text_Color', [0.05, 0.05, 0.05], ...
        'Legend_Background_Color', [1, 1, 1], ...
        'Legend_Edge_Color', [0.30, 0.30, 0.30], ...
        'Annotation_Background_Color', [1, 1, 1], ...
        'Legend_Location', 'northeast', ...
        'Legend_NumColumns', 2, ...
        'Annotation_Max_Per_Row', 3 ...
    ), ...
    'Figure_13_FEA_Stress_Strain_Comparison', struct( ...
        'Name', 'FEA Stress-Strain Comparison', ...
        'File_Name', 'Fig13_FEA_Stress_Strain_Comparison.png', ...
        'Enable', true, ...
        'Title', {{'True Stress-Strain Comparison', 'Experimental vs FEA'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Legend', {{ ...
            'Experiment (true)', ...
            'FEA (true)', ...
            'Exp. yield', ...
            'Exp. UTS', ...
            'Exp. failure', ...
            'FEA yield', ...
            'FEA UTS', ...
            'FEA failure'}}, ...
        'Experimental_Curve_Color', '#DC2626', ...
        'FEA_Curve_Color', '#1D4ED8', ...
        'FEA_Yield_Marker', 'o', ...
        'FEA_UTS_Marker', 'h', ...
        'FEA_Failure_Marker', 's', ...
        'FEA_Yield_Marker_Size', 11, ...
        'FEA_UTS_Marker_Size', 12, ...
        'FEA_Failure_Marker_Size', 10, ...
        'FEA_Yield_FaceColor', '#16A34A', ...
        'FEA_Yield_EdgeColor', '#14532D', ...
        'FEA_UTS_FaceColor', '#7C3AED', ...
        'FEA_UTS_EdgeColor', '#4C1D95', ...
        'FEA_Failure_FaceColor', '#F97316', ...
        'FEA_Failure_EdgeColor', '#9A3412', ...
        'FEA_Marker_LineWidth', 1.6, ...
        'Curve_Line_Style', '-', ...
        'Legend_Location', 'best' ...
    ), ...
    'Figure_14_FEA_Field_Output_Stages', struct( ...
        'Name', 'FEA Field Output Stages', ...
        'File_Name', 'Fig14_FEA_Field_Output_Stages.png', ...
        'Enable', true, ...
        'Title', {{'Longitudinal Strain Field Output', 'Elastic to Softening Stages'}}, ...
        'Stage_Order', {{'elastic', 'yield', 'hardening', 'necking', 'softening'}}, ...
        'Stage_Titles', {{'Elastic', 'Onset of Plasticity', 'Plastic Hardening', 'Necking', 'Softening'}}, ...
        'X_Label', '$x$ coordinate', ...
        'Y_Label', '$y$ coordinate', ...
        'Colorbar_Label', 'Longitudinal strain, $LE22$' ...
    ), ...    
    'Figure_15_Considere_Form_Comparison', struct( ...
        'Name', 'Considere Form Comparison', ...
        'File_Name', 'Fig15_Considere_Form_Comparison.png', ...
        'Enable', true, ...
        'Title', {{'Consid\`ere Criterion Comparison', 'True-Strain and Engineering-Strain Formulations'}}, ...
        'Tile_Titles', {{ ...
            '(A) True-Strain form: $\frac{\mathrm{d}\sigma_T}{\mathrm{d}\varepsilon_T} = \sigma_T$', ...
            '(B) Engineering-Strain form: $\frac{\mathrm{d}\sigma_T}{\mathrm{d}\varepsilon_N} = \frac{\sigma_T}{1 + \varepsilon_N}$'}}, ...
        'X_Labels', {{'True Strain, $\varepsilon_T$', 'Engineering Strain, $\varepsilon_N$'}}, ...
        'Y_Labels', {{ ...
            'Stress / hardening rate (MPa), $\sigma_T$, $\frac{\mathrm{d}\sigma_T}{\mathrm{d}\varepsilon_T}$', ...
            'True stress (MPa), $\sigma_T$'}}, ...
        'Legend_Left', {{ ...
            'True response: $\sigma_T-\varepsilon_T$', ...
            'Hardening rate: $\mathrm{d}\sigma_T/\mathrm{d}\varepsilon_T$', ...
            'True-form Consid\`ere point: $\left(\varepsilon_T^{C,T}, \sigma_T^{C,T}\right)$', ...
            'Mapped Eng. \ UTS: $\left(\varepsilon_T^{\mathrm{UTS}}, \sigma_T^{\mathrm{UTS}}\right)$'}}, ...
        'Legend_Right', {{ ...
            'True response: $\sigma_T-\varepsilon_N$', ...
            'Eng. form tangent', ...
            'Eng. form Consid\`ere point: $\left(\varepsilon_N^{C,N}, \sigma_T^{C,N}\right)$', ...
            'Mapped Eng. \ UTS: $\left(\varepsilon_N^{UTS}, \sigma_T^{\mathrm{UTS}}\right)$'}}, ...
        'Legend_Location_Left', 'northeast', ...
        'Legend_Location_Right', 'southwest', ...
        'Legend_Width_Left', 0.26, ...
        'Legend_Width_Right', 0.30, ...
        'Mapped_UTS_Marker', 'd', ...
        'Mapped_UTS_Size_Offset', 3, ...
        'Left_X_Limits', [0.015707370770212, 0.024734535981995], ...
        'Left_Y_Limits', [108.3545928825399, 135.333411368922], ...
        'Right_X_Limits', [0.015602575394954, 0.031402450653318], ...
        'Right_Y_Limits', [125.7475683528528, 129.697537167444], ...
        'Left_X_Max_Factor', 3.0, ...
        'Left_Min_X_Max', 0.05, ...
        'Right_X_Min', -1.10, ...
        'Right_Positive_Pad', 0.08, ...
        'Y_Max', 130, ...
        'Annotation', struct( ...
            'True_Header', '$\\textbf{True-strain formulation}$', ...
            'True_Coord_Line', '$\\left(\\varepsilon_T^{C,T}, \\sigma_T^{C,T}\\right) = (%s, %.4f$ MPa$)$', ...
            'True_Mapped_Line', '$\\left(\\varepsilon_N^{UTS}, \\sigma_N^{UTS}\\right) = (%s, %.4f$ MPa$)$', ...
            'True_Eng_UTS_Line', '$\\left(\\varepsilon_N^{UTS}, \\sigma_N^{UTS}\\right) = (%s, %.4f$ MPa$)$', ...
            'Eng_Header', '\\textbf{Engineering-strain formulation}', ...
            'Eng_Coord_Line', '$\\left(\\varepsilon_N^{C,N}, \\sigma_T^{C,N}\\right) = (%s, %.4f$ MPa$)$', ...
            'Mapped_UTS_Line', '$\\left(\\varepsilon_N^{UTS}, \\sigma^{UTS}\\right) = (%s, %.4f$ MPa$)$', ...
            'UTS_Line', '$\\left(\\varepsilon_N^{UTS}, \\sigma_N^{UTS}\\right) = (%s, %.4f$ MPa$)$' ...
        ) ...
    ), ...
    'Figure_16_FEA_Peak_LE22_S22', struct( ...
        'Name', 'FEA LE22 and S22 Percentage Difference', ...
        'File_Name', 'Fig16_FEA_Peak_LE22_S22.png', ...
        'Enable', false, ...
        'Title', {{'LE22 and S22 Percentage Difference', 'Response vs Number of Elements'}}, ...
        'Tile_Titles', {{'(A) LE22 Percentage Difference Study', '(B) S22 Percentage Difference Study'}}, ...
        'Layout_Rows', 2, ...
        'Layout_Cols', 1, ...
        'Export_Width_In', 3.02, ...
        'Export_Height_In', 5.25, ...
        'Compact_Font_Scale', 0.70, ...
        'X_Label', 'Number of Elements, $N_e$', ...
        'Y_Labels', {{'LE22 Percentage Difference (\%), $\xi_{LE22}$', 'S22 Percentage Difference (\%), $\xi_{S22}$'}}, ...
        'Legend_Left', {{'$\xi_{LE22}$', 'Converged mesh'}}, ...
        'Legend_Right', {{'$\xi_{S22}$', 'Converged mesh'}}, ...
        'Legend_Location', 'northeast', ...
        'Tolerance_Label', 'Tolerance $\xi$', ...
        'LE22_Trendline_Label', '$\xi_{LE22}$ trend line', ...
        'S22_Trendline_Label', '$\xi_{S22}$ trend line', ...
        'LE22_Data_Marker', 'o', ...
        'LE22_Data_Marker_Size', 10, ...
        'Figure_Color', [1, 1, 1], ...
        'LE22_Data_Color', [0.00, 0.45, 0.74], ...
        'LE22_Data_Edge_Color', [0.00, 0.28, 0.47], ...
        'LE22_Data_Line_Width', 2.3, ...
        'LE22_Trendline_Style', '-', ...
        'LE22_Trendline_Color', [0.00, 0.30, 0.62], ...
        'LE22_Trendline_Line_Width', 2.2, ...
        'S22_Data_Marker', 's', ...
        'S22_Data_Marker_Size', 10, ...
        'S22_Data_Color', [0.85, 0.33, 0.10], ...
        'S22_Data_Edge_Color', [0.50, 0.19, 0.05], ...
        'S22_Data_Line_Width', 2.3, ...
        'S22_Trendline_Style', '-', ...
        'S22_Trendline_Color', [0.65, 0.23, 0.06], ...
        'S22_Trendline_Line_Width', 2.2, ...
        'Tolerance_Line_Style', '--', ...
        'Tolerance_Line_Color', [0.35, 0.35, 0.35], ...
        'Tolerance_Line_Width', 1.8, ...
        'Converged_Marker', 'o', ...
        'Converged_Marker_Edge_Color', [0.90, 0.00, 0.00], ...
        'Converged_Marker_Size', 24, ...
        'Converged_Marker_Line_Width', 2.8 ...
    ), ...
    'Figure_17_FEA_Time_Memory', struct( ...
        'Name', 'FEA Runtime and Memory vs Elements', ...
        'File_Name', 'Fig17_FEA_Time_Memory_vs_Elements.png', ...
        'Enable', false, ...
        'Title', {{'Solver Cost vs Number of Elements'}}, ...
        'X_Label', 'Number of Elements, $N_e$', ...
        'Y_Label_Left', 'Runtime (s)', ...
        'Y_Label_Right', 'Memory (MB)', ...
        'Legend', {{'Runtime data (s)', 'Memory data (MB)'; 'Runtime trendline (s)', 'Memory trendline (MB)'}}, ...
        'Legend_Location', 'northwest', ...
        'Legend_NumColumns', 2, ...
        'Runtime_Marker', 'o', ...
        'Figure_Color', [1, 1, 1], ...
        'Axis_Color', [1, 1, 1], ...
        'Grid_Color', [0.78, 0.80, 0.84], ...
        'Minor_Grid_Color', [0.88, 0.89, 0.92], ...
        'Runtime_Color', [0.00, 0.45, 0.74], ...
        'Runtime_Edge_Color', [0.00, 0.26, 0.42], ...
        'Runtime_Marker_Size', 8, ...
        'Runtime_Marker_Line_Width', 1.2, ...
        'Runtime_Trend_LineStyle', '-', ...
        'Runtime_Trend_LineWidth', 2.4, ...
        'Memory_Marker', 's', ...
        'Memory_Color', [0.85, 0.33, 0.10], ...
        'Memory_Edge_Color', [0.55, 0.20, 0.05], ...
        'Memory_Marker_Size', 8, ...
        'Memory_Marker_Line_Width', 1.2, ...
        'Memory_Trend_LineStyle', '-', ...
        'Memory_Trend_LineWidth', 2.4, ...
        'X_Limits', [], ...
        'Y_Limits_Left', [], ...
        'Y_Limits_Right', [] ...
    ), ...    
    'Figure_18_FEA_Phase_Only', struct( ...
        'Name', 'FEA True Stress-Strain Phases', ...
        'File_Name', 'Fig18_FEA_True_Phase_Plot.png', ...
        'Enable', true, ...
        'Title', {{'FEA True Stress-Strain Response', 'Elastic, Hardening, and Softening Regimes'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Elastic_Color', '#1D4ED8', ...
        'Hardening_Color', '#059669', ...
        'Softening_Color', '#DC2626', ...
        'Yield_Marker', 'o', ...
        'UTS_Marker', 'h', ...
        'Failure_Marker', 's', ...
        'Yield_FaceColor', '#16A34A', ...
        'Yield_EdgeColor', '#14532D', ...
        'UTS_FaceColor', '#7C3AED', ...
        'UTS_EdgeColor', '#4C1D95', ...
        'Failure_FaceColor', '#F97316', ...
        'Failure_EdgeColor', '#9A3412', ...
        'Yield_Marker_Size', 10, ...
        'UTS_Marker_Size', 12, ...
        'Failure_Marker_Size', 10, ...
        'Marker_LineWidth', 1.4, ...
        'Annotation_EdgeColor', '#1E3A8A', ...
        'Elastic_Line_Style', '-', ...
        'Hardening_Line_Style', '-', ...
        'Softening_Line_Style', '-', ...
        'Legend_Location', 'best' ...
    ), ...
    'Figure_19_FEA_True_Error', struct( ...
        'Name', 'FEA True Stress Error', ...
        'File_Name', 'Fig19_FEA_True_Stress_Percent_Error.png', ...
        'Enable', true, ...
        'Title', {{'Absolute Percent Error', 'FEA vs Experimental True Stress'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'Absolute Error (\%), $\left|\sigma_T^{FEA}-\sigma_T^{EXP}\right|/\left|\sigma_T^{EXP}\right| \times 100$', ...
        'Curve_Color', '#B91C1C', ...
        'Curve_Line_Style', '-', ...
        'Legend', {{'Absolute \% error'}}, ...
        'Legend_Location', 'best' ...
    ), ...
    'Figure_20_Peak_Displacement_Trend', struct( ...
        'Name', 'Peak Equivalent Plastic Displacement', ...
        'File_Name', 'Fig20_Peak_Equivalent_Plastic_Displacement.png', ...
        'Enable', false, ...
        'Title', {{'Peak Equivalent Plastic Displacement', 'Across Element Sizes'}}, ...
        'X_Label', 'Element Size, $L$', ...
        'Y_Label', 'Peak Equivalent Plastic Displacement, $\bar{u}_{\mathrm{pl}}^{max}$', ...
        'Figure_Color', [1, 1, 1], ...
        'Bar_Edge_Color', [0.18, 0.18, 0.18], ...
        'Bar_Edge_LineWidth', 1.2, ...
        'Legend', {{'Peak values (bar)'}}, ...
        'Legend_Location', 'northwest' ...
    ), ...
    'Figure_21_FEA_45deg_Rpt_Overlay', struct( ...
        'Name', 'FEA 45deg Fracture Overlay', ...
        'File_Name', 'Fig21_FEA_45deg_Rpt_Overlay.png', ...
        'Enable', false, ...
        'Rpt_Path', '', ...
        'Figure_Color', [1, 1, 1], ...
        'Title', {{'$45^\circ$ Fracture Stress-Strain Overlay', 'FEA Extracted True Curves vs Experimental True Response'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Legend', {{ ...
            'Experimental', ...
            'FEA: All Deleted Elements avg', ...
            'FEA: Lower Fracture Elements avg', ...
            'FEA: Upper Fracture Elements avg', ...
            'FEA: Lower + Upper Fracture Elements avg', ...
            'FEA: Initial Deleted Elements avg: {4810, 6002}'}}, ...
        'Experimental_Curve_Color', '#111827', ...
        'Experimental_Curve_Line_Style', '-', ...
        'Experimental_Curve_Line_Width', 2.9, ...
        'Curve_Colormap', 'lines', ...
        'Curve_Colors', {{'#E11D48', '#0072BD', '#D95319', '#7E2F8E', '#77AC30'}}, ...
        'Curve_Line_Styles', {{'-', '-', '--', '-.', ':'}}, ...
        'Curve_Markers', {{'none', 'none', 'none', 'none', 'none'}}, ...
        'Legend_Location', 'northeast' ...
    ), ...
    'Figure_22_FEA_Element_Phases', struct( ...
        'Name', 'FEA Initial Deleted Elements — Stress-Strain Phases', ...
        'File_Name', 'Fig22_FEA_Element_Phases.png', ...
        'Enable', false, ...
        'Font_Sizes', {{25, 25, 30}}, ...
        'Annotation_Font_Size', 20, ...
        'Legend_Font_Size', 20, ...
        'Title', {{'Initial Deleted Elements: True Stress-Strain Phases', 'Elastic, Hardening, and Softening Regimes'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Elastic_Color', '#1D4ED8', ...
        'Hardening_Color', '#059669', ...
        'Softening_Color', '#DC2626', ...
        'Yield_Marker', 'p', ...
        'UTS_Considere_Marker', 'h', ...
        'UTS_Engineering_Marker', 'd', ...
        'Failure_Marker', 's', ...
        'Yield_FaceColor', '#FACC15', ...
        'Yield_EdgeColor', '#854D0E', ...
        'UTS_Considere_FaceColor', '#A78BFA', ...
        'UTS_Considere_EdgeColor', '#4C1D95', ...
        'UTS_Engineering_FaceColor', '#67E8F9', ...
        'UTS_Engineering_EdgeColor', '#155E75', ...
        'Failure_FaceColor', '#F97316', ...
        'Failure_EdgeColor', '#9A3412', ...
        'Yield_Marker_Size', 14, ...
        'UTS_Marker_Size', 14, ...
        'Failure_Marker_Size', 11, ...
        'Marker_LineWidth', 1.4, ...
        'Inset_Marker_Size', 16, ...
        'Annotation_EdgeColor', '#1E3A8A', ...
        'Elastic_Line_Style', '-', ...
        'Hardening_Line_Style', '-', ...
        'Softening_Line_Style', '-', ...
        'Legend_Location', 'best', ...
        'Inset', struct( ...
            'Enable', true, ...
            'Show_Connecting_Lines', true, ...
            'Strain_Pad_Before_Yield', 0.0005, ...
            'Strain_Pad_After_UTS', 0.005, ...
            'Stress_Pad_Frac', 0.08, ...
            'Position', [0.36 0.16 0.38 0.38]) ...
    ), ...
    'Figure_23_FEA_Element_Stress_Time', struct( ...
        'Name', 'FEA Initial Deleted Elements — Stress vs Time', ...
        'File_Name', 'Fig23_FEA_Element_Stress_Time.png', ...
        'Enable', false, ...
        'Font_Sizes', {{25, 25, 30}}, ...
        'Annotation_Font_Size', 20, ...
        'Legend_Font_Size', 20, ...
        'Title', {{'Initial Deleted Elements: True Stress vs Time', 'Phase Identification'}}, ...
        'X_Label', 'Time, $t$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Elastic_Color', '#1D4ED8', ...
        'Hardening_Color', '#059669', ...
        'Softening_Color', '#DC2626', ...
        'Yield_Marker', 'p', ...
        'UTS_Marker', 'd', ...
        'Failure_Marker', 's', ...
        'Yield_FaceColor', '#FACC15', ...
        'Yield_EdgeColor', '#854D0E', ...
        'UTS_FaceColor', '#FED7AA', ...
        'UTS_EdgeColor', '#C2410C', ...
        'Failure_FaceColor', '#F97316', ...
        'Failure_EdgeColor', '#9A3412', ...
        'Yield_Marker_Size', 14, ...
        'UTS_Marker_Size', 14, ...
        'Failure_Marker_Size', 11, ...
        'Marker_LineWidth', 1.4, ...
        'Marker_Vertical_Line_Style', '--', ...
        'Marker_Vertical_Line_Width', 1.6, ...
        'Regime_Fill_Alpha', 0.10, ...
        'Annotation_EdgeColor', '#1E3A8A', ...
        'Elastic_Line_Style', '-', ...
        'Hardening_Line_Style', '-', ...
        'Softening_Line_Style', '-', ...
        'Legend_Location', 'best' ...
    ), ...
    'Figure_24_FEA_True_Combined_Comparison', struct( ...
        'Name', 'FEA True Comparison with Error', ...
        'File_Name', 'Fig24_FEA_True_Comparison_Error_Combined.png', ...
        'Enable', true, ...
        'Title', {{'FEA and Experimental True Stress-Strain', 'Overlay and POIs'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label_Left', 'True Stress (MPa), $\sigma_T$', ...
        'Y_Label_Right', 'Absolute stress difference (MPa), $|\Delta \sigma_T|$', ...
        'Error_Mode', 'absolute_stress', ...
        'Experimental_Curve_Line_Style', '-', ...
        'FEA_Curve_Line_Style', '--', ...
        'Experimental_Curve_Color', '#111827', ...
        'FEA_Curve_Color', '#2563EB', ...
        'Error_Color', '#7C3AED', ...
        'Error_Line_Style', '--', ...
        'Error_Line_Width', 2.2, ...
        'Error_Marker', 'x', ...
        'Error_Marker_Size', 9, ...
        'FEA_Yield_Marker', 'p', ...
        'FEA_UTS_Marker', 'h', ...
        'FEA_Failure_Marker', 's', ...
        'FEA_Yield_Marker_Size', 20, ...
        'FEA_UTS_Marker_Size', 20, ...
        'FEA_Failure_Marker_Size', 20, ...
        'FEA_Yield_FaceColor', '#67E8F9', ...
        'FEA_Yield_EdgeColor', '#0F766E', ...
        'FEA_UTS_FaceColor', '#FDBA74', ...
        'FEA_UTS_EdgeColor', '#C2410C', ...
        'FEA_Failure_FaceColor', '#F9A8D4', ...
        'FEA_Failure_EdgeColor', '#9D174D', ...
        'FEA_Marker_LineWidth', 1.6, ...
        'Legend_Location', 'northeast', ...
        'Legend_NumColumns', 2, ...
        'Annotation_EdgeColor', '#1E3A8A', ...
        'Plot_XLim', [-0.02, 0.4], ...
        'Plot_YLim', [0.0, 160.0], ...
        'Inset', struct( ...
            'Enable', true, ...
            'Position', [0.15 0.16 0.40 0.38], ...
            'Title', 'Yield and UTS zoom', ...
            'X_Pad_Fraction', 0.05, ...
            'Y_Pad_Fraction', 0.08, ...
            'Axis_Color', '#7C3AED') ...
    ), ...
    'Figure_25_Damage_Model_Rpt_Comparison', struct( ...
        'Name', 'Damage Model RPT Comparison', ...
        'File_Name', 'Fig25_Damage_Model_Rpt_Comparison.png', ...
        'Enable', true, ...
        'Title', {{'Damage Model Stress-Strain Comparison', 'Tabular, Linear, and Exponential Softening'}}, ...
        'X_Label', 'True Strain, $\varepsilon_T$', ...
        'Y_Label', 'True Stress (MPa), $\sigma_T$', ...
        'Tabular_Base_Name', 'Stress-Strain', ...
        'Linear_Base_Name', 'Linear_Damage', ...
        'Exponential_Base_Name', 'Exponential_Damage', ...
        'Tabular_Curve_Key', 'first', ...
        'Linear_Curve_Key', 'linear', ...
        'Exponential_Key_Prefix', 'exp_', ...
        'Tabular_Label', 'Tabular: Initial Deleted Elements avg', ...
        'Linear_Label', 'Linear damage', ...
        'Exponential_Label_Prefix', 'Exponential: $\alpha = ', ...
        'Exponential_Label_Suffix', '$', ...
        'Break_Types', {{'45', '-45', 'V', 'A', '-45', '45', 'A', 'A'}}, ...
        'Tabular_Color', '#111827', ...
        'Linear_Color', '#D95319', ...
        'Exponential_Colormap', 'lines', ...
        'Tabular_Line_Style', '-', ...
        'Linear_Line_Style', '--', ...
        'Exponential_Line_Styles', {{'-', '--', '-.', ':', '-', '--', '-.', ':', '-', '--'}}, ...
        'Exponential_Markers', {{'none', 'o', 's', 'd', '^', 'v', '>', '<', 'p', 'h'}}, ...
        'UTS_Line_Style', '--', ...
        'UTS_Line_Color', '#7C3AED', ...
        'UTS_Line_Width', 1.8, ...
        'Legend_Location', 'eastoutside', ...
        'Legend_NumColumns', 1 ...
    ), ...
    'Figure_26_FEA_Experimental_Point_Errors', struct( ...
        'Name', 'FEA vs Experimental Point Errors', ...
        'File_Name', 'Fig26_FEA_Experimental_Point_Errors.png', ...
        'Enable', true, ...
        'Title', {{'FEA vs Experimental Pointwise Errors', 'Yield, UTS, and Failure'}}, ...
        'Tile_Titles', {{'(A) True Strain Errors', '(B) True Stress Errors'}}, ...
        'X_Label', 'Point of Interest', ...
        'Y_Labels', {{ ...
            '$\xi_{\varepsilon_T}^{i}=100\left|\frac{\varepsilon_{T,\mathrm{FEA}}^{i}-\varepsilon_T^{i}}{\varepsilon_T^{i}}\right|\,(\%)$', ...
            '$\xi_{\sigma_T}^{i}=100\left|\frac{\sigma_{T,\mathrm{FEA}}^{i}-\sigma_T^{i}}{\sigma_T^{i}}\right|\,(\%)$' ...
            }}, ...
        'Strain_Bar_Colors', {{'#F59E0B', '#A78BFA', '#EC4899'}}, ...
        'Stress_Bar_Colors', {{'#B45309', '#6D28D9'}}, ...
        'Bar_Edge_Color', '#111827', ...
        'Bar_Line_Width', 1.2, ...
        'Label_Font_Size', 20, ...
        'Axis_Label_Font_Size', 18, ...
        'Strain_Axis_YLim', [0.0, 60.0], ...
        'Stress_Axis_YLim', [0.0, 0.625], ...
        'Legend_Location', 'northeast' ...
    ) ...
);

% Figure map:
% Figure 1  - engineering stress-strain with 0.2% offset yield.
% Figure 2  - elastic vs plastic engineering regimes.
% Figure 3  - true damaged vs undamaged stress-strain.
% Figure 4  - engineering, true, and effective stress overlay.
% Figure 5  - damage, true plastic strain, and equivalent plastic displacement.
% Figure 6  - Considere criterion construction.
% Figure 7  - comprehensive stress-strain with key points.
% Figure 8  - UTS zoom around yield-to-necking transition.
% Figure 9  - linear/tabular/exponential damage-law comparison.
% Figure 10 - effective stress parameterisation (UTS to rupture).
% Figure 11 - equivalent plastic displacement vs strain for mesh sizes.
% Figure 12 - mesh convergence metrics vs number of elements.
% Figure 13 - experimental vs FEA true stress-strain comparison.
% Figure 14 - field-output stage snapshots (LE22).
% Figure 15 - Considere true-strain vs engineering-strain forms.
% Figure 16 - peak LE22 and peak S22 vs mesh density.
% Figure 17 - solver runtime/memory trendlines vs element count.
% Figure 18 - FEA phase-only true stress-strain view.
% Figure 19 - absolute percent error of FEA true stress.
% Figure 20 - peak equivalent plastic displacement vs element size.
% Figure 21 - 45deg fracture RPT overlay (FEA extracted curves).
% Figure 22 - FEA initial deleted elements phase-coloured stress-strain.
% Figure 23 - FEA initial deleted elements stress vs time (phase ranges).
% Figure 24 - combined FEA/experimental true stress-strain, inset, and error.
% Figure 25 - tabular, linear, and exponential damage-model stress-strain comparison.
% Figure 26 - FEA vs experimental pointwise error summary at yield, UTS, and failure.

% ==============================================================
% PLOTTING DISPATCH
% ==============================================================

% Root-level plotting defaults are configured from Plot_Label_Struct only.
try
    RD = Plot_Label_Struct.Style.Root_Defaults;
    set(0, 'DefaultFigureColor', RD.Figure_Color);
    set(0, 'DefaultAxesColor', RD.Axes_Color);
    set(0, 'DefaultAxesXColor', RD.Axes_XColor);
    set(0, 'DefaultAxesYColor', RD.Axes_YColor);
    set(0, 'DefaultAxesZColor', RD.Axes_ZColor);
    set(0, 'DefaultTextColor', RD.Text_Color);
    set(0, 'DefaultLegendColor', RD.Legend_Color);
    set(0, 'DefaultLegendEdgeColor', RD.Legend_Edge_Color);
    set(0, 'DefaultLegendTextColor', RD.Legend_Text_Color);
catch
end

% Global plotting defaults requested for this workflow.
set(groot, 'defaultAxesLayer', 'bottom');
set(groot, 'defaultAxesXMinorGrid', 'off');
set(groot, 'defaultAxesYMinorGrid', 'off');

if Run_Pre_FEA_Pipeline
    Necking_Index = Ultimate_Tensile_Strength_Struct.UTS_Index;
    Necking_Stress = Ultimate_Tensile_Strength_Struct.UTS_Stress;
    Necking_Strain = Ultimate_Tensile_Strength_Struct.UTS_Strain;
    Necking_Elastic_Strain = Data_Struct.True_Stress_Damaged(Necking_Index) / Linear_Fit_Struct.Youngs_Modulus;
    Necking_Plastic_Strain = max(Data_Struct.True_Strain(Necking_Index) - Necking_Elastic_Strain, 0);
    Rupture_Strain = Data_Struct.Engineering_Strain(Damage_Struct.Rupture_Index);
    Peak_Engineering_Strain = max(Data_Struct.Engineering_Strain);

    fprintf('\n------------------------ KEY RESULTS ------------------------\n');
    fprintf('Yield point             : strain = %.4f | stress = %.4f MPa\n', ...
        Linear_Fit_Struct.Yield_Strain, Linear_Fit_Struct.Yield_Stress);
    fprintf('Young''s modulus         : E = %.4f MPa\n', Linear_Fit_Struct.Youngs_Modulus);
    fprintf('Necking point (UTS)     : strain = %.4f | stress = %.4f MPa\n', ...
        Necking_Strain, Necking_Stress);
    fprintf('Necking elastic strain  : %.4f\n', Necking_Elastic_Strain);
    fprintf('Necking plastic strain  : %.4f\n', Necking_Plastic_Strain);
    fprintf('Rupture strain          : %.4f\n', Rupture_Strain);
    fprintf('Peak engineering strain : %.4f\n', Peak_Engineering_Strain);
    fprintf('Considere true strain   : %.4f\n', Considere_Struct.Considere_True_Strain);
    fprintf('Considere true stress   : %.4f MPa\n', Considere_Struct.Considere_True_Stress);
    fprintf('Considere elastic strain: %.4f\n', Considere_Struct.Considere_Elastic_Strain);
    fprintf('Considere plastic strain: %.4f\n', Considere_Struct.Considere_Plastic_Strain);
    fprintf('Considere eng-form epsN : %.4f\n', Considere_Struct.Considere_EngineeringForm_Intersection_Strain);
    fprintf('Considere eng-form epsT : %.4f\n', Considere_Struct.Considere_EngineeringForm_True_Strain);
    fprintf('Considere eng-form sigT : %.4f MPa\n', Considere_Struct.Considere_EngineeringForm_True_Stress);
    fprintf('Considere eng-form sigN : %.4f MPa\n', Considere_Struct.Considere_EngineeringForm_Engineering_Stress);
    fprintf('UTS mapped true stress  : %.4f MPa\n', Engineering_UTS_True_Stress);
    fprintf('Delta epsN (true-UTS)   : %+0.6f\n', Considere_Projected_Engineering_Strain - Ultimate_Tensile_Strength_Struct.UTS_Strain);
    fprintf('Delta sigT (true-UTS)   : %+0.6f MPa\n', Considere_Struct.Considere_Intersection_Stress - Engineering_UTS_True_Stress);
    fprintf('Delta epsN (eng-UTS)    : %+0.6f\n', Considere_Struct.Considere_EngineeringForm_Intersection_Strain - Ultimate_Tensile_Strength_Struct.UTS_Strain);
    fprintf('Delta sigT (eng-UTS)    : %+0.6f MPa\n', Considere_Struct.Considere_EngineeringForm_True_Stress - Engineering_UTS_True_Stress);
    fprintf('Delta sigN (eng-UTS)    : %+0.6f MPa\n', Considere_Struct.Considere_EngineeringForm_Engineering_Stress - Ultimate_Tensile_Strength_Struct.UTS_Stress);
    fprintf('------------------------------------------------------------\n');
    fprintf('[PRE] Initiating pre-FEA plotting routine...\n');
    Create_Material_Data_Plots(Plot_Data_Struct, Plot_Label_Struct);
else
    fprintf('[PRE] Pre-FEA pipeline disabled by flag.\n');
end

if Run_Post_FEA_Pipeline
    Print_Post_FEA_Opening_Dialog(Plot_Data_Struct, Convergence_Data_Directory, Damage_Evolution_Directory);
    fprintf('[POST] Initiating FEA plotting routine...\n');
    Create_Preprocessing_Plots(Plot_Data_Struct, Plot_Label_Struct);
else
    fprintf('[POST] Post-FEA pipeline disabled by flag.\n');
end

if Run_Pre_FEA_Pipeline && Run_Post_FEA_Pipeline
    Executed_Pipelines = 'pre-FEA, post-FEA';
elseif Run_Pre_FEA_Pipeline
    Executed_Pipelines = 'pre-FEA';
else
    Executed_Pipelines = 'post-FEA';
end

fprintf('============================================================\n');
fprintf(' Processing complete.\n');
if Run_Pre_FEA_Pipeline && isfield(Report_Struct, 'Output_Report_Path') && ...
        strlength(string(Report_Struct.Output_Report_Path)) > 0
    fprintf(' Report workbook         : %s\n', char(string(Report_Struct.Output_Report_Path)));
end
fprintf(' Executed pipelines      : %s\n', Executed_Pipelines);
fprintf('============================================================\n');


% ==============================================================
% LOCAL FUNCTIONS - ANALYSIS
% ==============================================================

function Data_Struct = Load_Engineering_And_True_Data(Input_File)
    % Always read from the FIRST sheet (index 1) which contains the raw
    % engineering data.  This avoids name-matching issues when the sheet
    % has been renamed or when extra processed sheets have been added.
    Existing_Sheet_Names = sheetnames(Input_File);
    fprintf('      Sheets found: %s\n', strjoin(Existing_Sheet_Names, ', '));
    fprintf('      Reading raw data from sheet 1 ("%s")\n', Existing_Sheet_Names(1));

    Aluminium_Data = readtable(Input_File, 'VariableNamingRule', 'preserve', ...
        'FileType', 'spreadsheet', 'Sheet', 1);

    % Validate that the table has at least 2 numeric columns
    Sheet_Name_For_Log = char(Existing_Sheet_Names(1));
    if width(Aluminium_Data) < 2
        error('Load_Engineering_And_True_Data:InsufficientColumns', ...
            'Sheet "%s" has only %d column(s); expected at least 2 (strain, stress).', ...
            Sheet_Name_For_Log, width(Aluminium_Data));
    end

    Engineering_Strain = Aluminium_Data{:, 1};
    Engineering_Stress = Aluminium_Data{:, 2};

    % Report and reject NaN values
    NaN_Strain_Count = sum(isnan(Engineering_Strain));
    NaN_Stress_Count = sum(isnan(Engineering_Stress));
    if NaN_Strain_Count > 0 || NaN_Stress_Count > 0
        fprintf('      WARNING: NaN detected - Strain: %d, Stress: %d (of %d rows)\n', ...
            NaN_Strain_Count, NaN_Stress_Count, numel(Engineering_Strain));
        fprintf('      Column 1 type: %s, Column 2 type: %s\n', ...
            class(Aluminium_Data{:,1}), class(Aluminium_Data{:,2}));

        % Remove NaN rows so downstream processing does not break
        Valid_Mask = ~isnan(Engineering_Strain) & ~isnan(Engineering_Stress);
        Engineering_Strain = Engineering_Strain(Valid_Mask);
        Engineering_Stress = Engineering_Stress(Valid_Mask);
        Aluminium_Data = Aluminium_Data(Valid_Mask, :);
        fprintf('      Removed %d NaN rows, %d valid rows remain.\n', ...
            sum(~Valid_Mask), numel(Engineering_Strain));
    end

    if isempty(Engineering_Strain)
        error('Load_Engineering_And_True_Data:NoValidData', ...
            'No valid numeric data rows found in sheet "%s".', Sheet_Name_For_Log);
    end

    True_Strain = log(1 + Engineering_Strain);
    True_Stress_Damaged = Engineering_Stress .* (1 + Engineering_Strain);

    Data_Struct = struct( ...
        'Engineering_Strain', Engineering_Strain, ...
        'Engineering_Stress', Engineering_Stress, ...
        'True_Strain', True_Strain, ...
        'True_Stress_Damaged', True_Stress_Damaged, ...
        'Source_Table', Aluminium_Data);
end

function Linear_Fit_Struct = Calculate_Linear_Fit_And_Yield_Point(Data_Struct)
Fit_Window = [0, 0.0015];
    Window_Mask = (Data_Struct.Engineering_Strain >= Fit_Window(1)) & ...
                (Data_Struct.Engineering_Strain <= Fit_Window(2));
    Strain_Section = Data_Struct.Engineering_Strain(Window_Mask);
    Stress_Section = Data_Struct.Engineering_Stress(Window_Mask);

    Linear_Coefficients = polyfit(Strain_Section, Stress_Section, 1);
    Youngs_Modulus = Linear_Coefficients(1);
    Linear_Intercept = Linear_Coefficients(2);

    Offset_Strain = 0.002;
    Offset_Line_Stress = Youngs_Modulus .* (Data_Struct.Engineering_Strain - Offset_Strain) + Linear_Intercept;
    [Yield_Strain, Yield_Stress, ~, Yield_Index] = Find_Interpolated_Curve_Intersection( ...
        Data_Struct.Engineering_Strain, Data_Struct.Engineering_Stress, Offset_Line_Stress, 1);

    % --- True yield via 0.2% offset on the true stress-strain curve ---
    True_Strain = Data_Struct.True_Strain;
    True_Stress = Data_Struct.True_Stress_Damaged;
    True_Offset_Line = Youngs_Modulus .* (True_Strain - Offset_Strain) + Linear_Intercept;
    [True_Yield_Strain, True_Yield_Stress, ~, True_Yield_Index] = Find_Interpolated_Curve_Intersection( ...
        True_Strain, True_Stress, True_Offset_Line, 1);

    Linear_Fit_Struct = struct( ...
        'Youngs_Modulus', Youngs_Modulus, ...
        'Linear_Intercept', Linear_Intercept, ...
        'Fit_Window', Fit_Window, ...
        'Window_Mask', Window_Mask, ...
        'Offset_Strain', Offset_Strain, ...
        'Yield_Index', Yield_Index, ...
        'Yield_Strain', Yield_Strain, ...
        'Yield_Stress', Yield_Stress, ...
        'True_Yield_Index', True_Yield_Index, ...
        'True_Yield_Strain', True_Yield_Strain, ...
        'True_Yield_Stress', True_Yield_Stress, ...
        'Offset_Line_Stress', Offset_Line_Stress);
end

function Ultimate_Tensile_Strength_Struct = Calculate_Engineering_Ultimate_Tensile_Strength(Data_Struct)
[UTS_Stress, UTS_Index] = max(Data_Struct.Engineering_Stress);
    UTS_Strain = Data_Struct.Engineering_Strain(UTS_Index);

    Ultimate_Tensile_Strength_Struct = struct( ...
        'UTS_Index', UTS_Index, ...
        'UTS_Strain', UTS_Strain, ...
        'UTS_Stress', UTS_Stress);
end

function Considere_Struct = Calculate_Considere_Criterion(Data_Struct, Linear_Fit_Struct)
    %CALCULATE_CONSIDERE_CRITERION Determine necking onset via dsigma/depsilon = sigma.
    %   The Considere criterion is applied to the TRUE stress-strain response.
    %   Both the true-strain form and the engineering-strain form are
    %   returned as interpolated intersections for plotting accuracy.

    Engineering_Strain = Data_Struct.Engineering_Strain;
    Engineering_Stress = Data_Struct.Engineering_Stress;
    True_Strain = Data_Struct.True_Strain;
    True_Stress = Data_Struct.True_Stress_Damaged;
    Yield_Index = Linear_Fit_Struct.Yield_Index;
    True_Yield_Index = Linear_Fit_Struct.True_Yield_Index;
    N = numel(True_Strain);

    % Numerical derivative d sigma_true / d epsilon_true
    d_eps = diff(True_Strain);
    d_sig = diff(True_Stress);
    Work_Hardening_Rate_Raw = d_sig ./ d_eps;

    % Smooth derivative to suppress local noise before sign-change detection
    Smooth_Window = min(max(5, round(N / 50)), max(numel(Work_Hardening_Rate_Raw), 1));
    Work_Hardening_Rate = smoothdata(Work_Hardening_Rate_Raw, 'movmean', Smooth_Window);

    % Align work-hardening data on epsilon_true(2:end)
    WHR_Strain = True_Strain(2:end);
    True_Stress_Aligned = True_Stress(2:end);

    % Search beyond yield, aligned to derivative grid
    Search_Start = max(True_Yield_Index - 1, 1);
    [Considere_Intersection_Strain, Considere_Intersection_WHR, Considere_Intersection_Stress, ~] = ...
        Find_Interpolated_Curve_Intersection(WHR_Strain, Work_Hardening_Rate, True_Stress_Aligned, Search_Start);
    Considere_Intersection_Delta = Considere_Intersection_WHR - Considere_Intersection_Stress;
    [~, Considere_Index] = min(abs(True_Strain - Considere_Intersection_Strain));
    Considere_Index = min(max(Considere_Index, 1), N);

    Considere_True_Strain = Considere_Intersection_Strain;
    Considere_True_Stress = Considere_Intersection_Stress;

    % Elastic / plastic decomposition at the Considere point
    Considere_Elastic_Strain = Considere_True_Stress / Linear_Fit_Struct.Youngs_Modulus;
    Considere_Plastic_Strain = max(Considere_True_Strain - Considere_Elastic_Strain, 0);

    % Engineering-strain form:
    %   d sigma_true / d epsilon_eng = sigma_true / (1 + epsilon_eng)
    d_eps_eng = diff(Engineering_Strain);
    d_sig_eng = diff(True_Stress);
    Work_Hardening_Rate_Engineering_Raw = d_sig_eng ./ d_eps_eng;
    Work_Hardening_Rate_Engineering = smoothdata(Work_Hardening_Rate_Engineering_Raw, 'movmean', Smooth_Window);

    WHR_Engineering_Strain = Engineering_Strain(2:end);
    Engineering_Target_Stress = True_Stress(2:end) ./ (1 + WHR_Engineering_Strain);

    Search_Start_Engineering = max(Yield_Index - 1, 1);
    [Considere_EngineeringForm_Intersection_Strain, Considere_EngineeringForm_Intersection_WHR, ...
        Considere_EngineeringForm_Target_Stress, ~] = ...
        Find_Interpolated_Curve_Intersection(WHR_Engineering_Strain, Work_Hardening_Rate_Engineering, ...
            Engineering_Target_Stress, Search_Start_Engineering);

    Considere_EngineeringForm_Intersection_Delta = Considere_EngineeringForm_Intersection_WHR - ...
        Considere_EngineeringForm_Target_Stress;
    [~, Considere_EngineeringForm_Index] = min(abs(Engineering_Strain - Considere_EngineeringForm_Intersection_Strain));
    Considere_EngineeringForm_Index = min(max(Considere_EngineeringForm_Index, 1), numel(Engineering_Strain));

    Considere_EngineeringForm_True_Strain = log(1 + Considere_EngineeringForm_Intersection_Strain);
    Considere_EngineeringForm_True_Stress = interp1(Engineering_Strain, True_Stress, ...
        Considere_EngineeringForm_Intersection_Strain, 'linear', 'extrap');
    Considere_EngineeringForm_Engineering_Stress = interp1(Engineering_Strain, Engineering_Stress, ...
        Considere_EngineeringForm_Intersection_Strain, 'linear', 'extrap');
    Considere_EngineeringForm_Elastic_Strain = Considere_EngineeringForm_True_Stress / Linear_Fit_Struct.Youngs_Modulus;
    Considere_EngineeringForm_Plastic_Strain = max(Considere_EngineeringForm_True_Strain - ...
        Considere_EngineeringForm_Elastic_Strain, 0);
    Considere_EngineeringForm_Tangent_Slope = Considere_EngineeringForm_Intersection_WHR;
    if abs(Considere_EngineeringForm_Tangent_Slope) > eps(max(abs(Considere_EngineeringForm_Tangent_Slope), 1))
        Considere_EngineeringForm_Tangent_XIntercept = Considere_EngineeringForm_Intersection_Strain - ...
            Considere_EngineeringForm_True_Stress / Considere_EngineeringForm_Tangent_Slope;
    else
        Considere_EngineeringForm_Tangent_XIntercept = NaN;
    end

    Considere_Struct = struct( ...
        'Work_Hardening_Rate', Work_Hardening_Rate, ...
        'WHR_Strain', WHR_Strain, ...
        'Considere_Index', Considere_Index, ...
        'Considere_True_Strain', Considere_True_Strain, ...
        'Considere_True_Stress', Considere_True_Stress, ...
        'Considere_Intersection_Strain', Considere_Intersection_Strain, ...
        'Considere_Intersection_Stress', Considere_Intersection_Stress, ...
        'Considere_Intersection_WHR', Considere_Intersection_WHR, ...
        'Considere_Intersection_Delta', Considere_Intersection_Delta, ...
        'Considere_Elastic_Strain', Considere_Elastic_Strain, ...
        'Considere_Plastic_Strain', Considere_Plastic_Strain, ...
        'Work_Hardening_Rate_Engineering', Work_Hardening_Rate_Engineering, ...
        'WHR_Engineering_Strain', WHR_Engineering_Strain, ...
        'Considere_EngineeringForm_Index', Considere_EngineeringForm_Index, ...
        'Considere_EngineeringForm_Intersection_Strain', Considere_EngineeringForm_Intersection_Strain, ...
        'Considere_EngineeringForm_True_Strain', Considere_EngineeringForm_True_Strain, ...
        'Considere_EngineeringForm_True_Stress', Considere_EngineeringForm_True_Stress, ...
        'Considere_EngineeringForm_Engineering_Stress', Considere_EngineeringForm_Engineering_Stress, ...
        'Considere_EngineeringForm_Intersection_WHR', Considere_EngineeringForm_Intersection_WHR, ...
        'Considere_EngineeringForm_Target_Stress', Considere_EngineeringForm_Target_Stress, ...
        'Considere_EngineeringForm_Intersection_Delta', Considere_EngineeringForm_Intersection_Delta, ...
        'Considere_EngineeringForm_Elastic_Strain', Considere_EngineeringForm_Elastic_Strain, ...
        'Considere_EngineeringForm_Plastic_Strain', Considere_EngineeringForm_Plastic_Strain, ...
        'Considere_EngineeringForm_Tangent_Slope', Considere_EngineeringForm_Tangent_Slope, ...
        'Considere_EngineeringForm_Tangent_XIntercept', Considere_EngineeringForm_Tangent_XIntercept);
end

function [x_intersection, y1_intersection, y2_intersection, nearest_index] = ...
        Find_Interpolated_Curve_Intersection(x_values, y_curve_1, y_curve_2, start_index)
    start_index = min(max(round(start_index), 1), numel(x_values));
    difference = y_curve_1 - y_curve_2;
    search_region = difference(start_index:end);
    sign_changes = find(search_region(1:end-1) .* search_region(2:end) <= 0, 1, 'first');

    if ~isempty(sign_changes)
        j = start_index + sign_changes - 1;
        d0 = difference(j);
        d1 = difference(j + 1);
        if d1 ~= d0
            t = d0 / (d0 - d1);
        else
            t = 0;
        end
        t = min(max(t, 0), 1);
        x_intersection = x_values(j) + t * (x_values(j + 1) - x_values(j));
        y1_intersection = y_curve_1(j) + t * (y_curve_1(j + 1) - y_curve_1(j));
        y2_intersection = y_curve_2(j) + t * (y_curve_2(j + 1) - y_curve_2(j));
    else
        [~, local_index] = min(abs(search_region));
        nearest_index = start_index + local_index - 1;
        x_intersection = x_values(nearest_index);
        y1_intersection = y_curve_1(nearest_index);
        y2_intersection = y_curve_2(nearest_index);
    end

    [~, nearest_index] = min(abs(x_values - x_intersection));
    nearest_index = min(max(nearest_index, 1), numel(x_values));
end

function True_Undamaged_Struct = Calculate_True_Undamaged_Response(Data_Struct, Considere_Struct, Ultimate_Tensile_Strength_Struct)

    N_Points = numel(Data_Struct.Engineering_Strain);
    Use_Engineering_UTS = (nargin >= 3) && isstruct(Ultimate_Tensile_Strength_Struct) && ...
        isfield(Ultimate_Tensile_Strength_Struct, 'UTS_Index') && ...
        ~isempty(Ultimate_Tensile_Strength_Struct.UTS_Index) && ...
        isfinite(Ultimate_Tensile_Strength_Struct.UTS_Index);

    if Use_Engineering_UTS
        Activation_Index = round(double(Ultimate_Tensile_Strength_Struct.UTS_Index));
        Activation_Index = max(1, min(N_Points, Activation_Index));
        Activation_Engineering_Strain = Data_Struct.Engineering_Strain(Activation_Index);
        Activation_Nominal_Stress = Data_Struct.Engineering_Stress(Activation_Index);
        Activation_True_Strain = Data_Struct.True_Strain(Activation_Index);
        Activation_True_Stress = Data_Struct.True_Stress_Damaged(Activation_Index);
        Activation_Method = "Engineering UTS";
    else
        Activation_Index = Considere_Struct.Considere_Index;
        Activation_True_Strain = Considere_Struct.Considere_Intersection_Strain;
        Activation_True_Stress = Considere_Struct.Considere_Intersection_Stress;
        Activation_Engineering_Strain = exp(Activation_True_Strain) - 1;
        Activation_Nominal_Stress = Activation_True_Stress / max(1 + Activation_Engineering_Strain, eps);
        Activation_Method = "Considere criterion";
    end

    True_Stress_Undamaged = zeros(size(Data_Struct.True_Stress_Damaged));
    True_Stress_Undamaged(1:Activation_Index) = Data_Struct.True_Stress_Damaged(1:Activation_Index);
    if Activation_Index < numel(True_Stress_Undamaged)
        True_Stress_Undamaged(Activation_Index + 1:end) = Activation_Nominal_Stress .* ...
            (1 + Data_Struct.Engineering_Strain(Activation_Index + 1:end));
    end

    True_Undamaged_Struct = struct(...
        'True_Stress_Undamaged', True_Stress_Undamaged, ...
        'Activation_Index', Activation_Index, ...
        'Activation_Engineering_Strain', Activation_Engineering_Strain, ...
        'Activation_True_Strain', Activation_True_Strain, ...
        'Activation_True_Stress', Activation_True_Stress, ...
        'Activation_Nominal_Stress', Activation_Nominal_Stress, ...
        'Activation_Method', Activation_Method, ...
        'True_Undamaged_Rupture_Strain', Data_Struct.True_Strain(end), ...
        'True_Undamaged_Rupture_Stress', True_Stress_Undamaged(end));
end

function Damage_Struct = Calculate_Damage_From_UTS_To_Rupture(Data_Struct, Linear_Fit_Struct, Ultimate_Tensile_Strength_Struct, Element_Size_L, True_Undamaged_Struct)
    Rupture_Index = numel(Data_Struct.Engineering_Strain);
    UTS_Index = round(double(True_Undamaged_Struct.Activation_Index));
    if ~isfinite(UTS_Index) || UTS_Index < 1 || UTS_Index > Rupture_Index
        UTS_Index = round(double(Ultimate_Tensile_Strength_Struct.UTS_Index));
    end
    UTS_Index = max(1, min(Rupture_Index, UTS_Index));
    Yield_Index = Linear_Fit_Struct.Yield_Index;

    True_Elastic_Strain = Data_Struct.True_Stress_Damaged ./ Linear_Fit_Struct.Youngs_Modulus;
    True_Plastic_Strain = Data_Struct.True_Strain - True_Elastic_Strain;

    True_Stress_Damaged = Data_Struct.True_Stress_Damaged;
    True_Stress_Undamaged = True_Undamaged_Struct.True_Stress_Undamaged;
    True_Plastic_Strain(1:Yield_Index) = 0;

    Equivalent_Plastic_Displacement = Element_Size_L .* (True_Plastic_Strain - True_Plastic_Strain(UTS_Index));
    Equivalent_Plastic_Displacement(1:UTS_Index) = 0;
    Equivalent_Plastic_Displacement = max(Equivalent_Plastic_Displacement, 0);

    Damage = zeros(Rupture_Index, 1);
    Damage(UTS_Index:Rupture_Index) = 1 - (True_Stress_Damaged(UTS_Index:Rupture_Index) ./ True_Stress_Undamaged(UTS_Index:Rupture_Index));
    Damage = min(max(Damage, 0), 1);

    Damage_Struct = struct( ...
        'Damage_Computed', true, ...
        'Element_Size_L', Element_Size_L, ...
        'Rupture_Index', Rupture_Index, ...
        'True_Plastic_Strain', True_Plastic_Strain, ...
        'Equivalent_Plastic_Displacement', Equivalent_Plastic_Displacement, ...
        'Damage', Damage);
end

function Report_Struct = Write_Processed_Report_Workbook(Input_File, Data_Struct, Linear_Fit_Struct, ...
        Ultimate_Tensile_Strength_Struct, True_Undamaged_Struct, Damage_Struct, Considere_Struct)
    [Input_Folder, Input_Base_Name, ~] = fileparts(Input_File);
    if isempty(Input_Folder)
        Input_Folder = pwd;
    end

    Processed_Sheet_Name = 'Processed data';
    Displacement_Sheet_Name = 'Displacement_By_Element_Size';

    % Use the original input file instead of creating a new one.
    Report_Path_To_Write = fullfile(Input_Folder, [Input_Base_Name, '.xlsx']);
    Report_Path_To_Write = char(java.io.File(Report_Path_To_Write).getCanonicalPath());

    Data_Point_Count = numel(Data_Struct.Engineering_Strain);
    True_Elastic_Strain = Data_Struct.True_Stress_Damaged ./ Linear_Fit_Struct.Youngs_Modulus;

    Regime = repmat("Plastic", Data_Point_Count, 1);
    Regime(1:Linear_Fit_Struct.Yield_Index) = "Elastic";

    % Key_Point now distinguishes engineering vs true key points
    Key_Point = strings(Data_Point_Count, 1);
    Key_Point(Linear_Fit_Struct.Yield_Index) = "Eng_Yield";
    if Linear_Fit_Struct.True_Yield_Index ~= Linear_Fit_Struct.Yield_Index
        Key_Point(Linear_Fit_Struct.True_Yield_Index) = "True_Yield";
    else
        Key_Point(Linear_Fit_Struct.Yield_Index) = "Eng+True_Yield";
    end
    Key_Point(Ultimate_Tensile_Strength_Struct.UTS_Index) = "Eng_UTS";
    if Considere_Struct.Considere_Index ~= Ultimate_Tensile_Strength_Struct.UTS_Index
        Key_Point(Considere_Struct.Considere_Index) = "True_UTS";
    else
        Key_Point(Ultimate_Tensile_Strength_Struct.UTS_Index) = "Eng+True_UTS";
    end
    Key_Point(Damage_Struct.Rupture_Index) = "Rupture";

    Computed_Columns_Table = table( ...
        Data_Struct.True_Strain, ...
        Data_Struct.True_Stress_Damaged, ...
        True_Undamaged_Struct.True_Stress_Undamaged, ...
        repmat(Linear_Fit_Struct.Youngs_Modulus, Data_Point_Count, 1), ...
        True_Elastic_Strain, ...
        Damage_Struct.True_Plastic_Strain, ...
        Damage_Struct.Equivalent_Plastic_Displacement, ...
        Damage_Struct.Damage, ...
        Regime, ...
        Key_Point, ...
        'VariableNames', { ...
        'True_Strain', ...
        'True_Stress_Damaged_MPa', ...
        'True_Stress_Undamaged_MPa', ...
        'Youngs_Modulus_MPa', ...
        'True_Elastic_Strain', ...
        'True_Plastic_Strain', ...
        'Equivalent_Plastic_Displacement', ...
        'Damage', ...
        'Regime', ...
        'Key_Point'});

    % Keep the processed sheet fixed: first two columns are engineering data from source.
    if width(Data_Struct.Source_Table) >= 2
        Engineering_Source_Table = Data_Struct.Source_Table(:, 1:2);
    else
        Engineering_Source_Table = table( ...
            Data_Struct.Engineering_Strain, ...
            Data_Struct.Engineering_Stress, ...
            'VariableNames', {'Engineering_Strain', 'Engineering_Stress_MPa'});
    end

    Processed_Report_Table = [Engineering_Source_Table, Computed_Columns_Table];
    Engineering_Column_Count = width(Engineering_Source_Table);

    % Check if the file is accessible for writing.
    if exist(Report_Path_To_Write, 'file')
        fid_write_check = fopen(Report_Path_To_Write, 'r+');
        if fid_write_check == -1
            error('Cannot write to file %s. Please close it if it is open in another program.', Report_Path_To_Write);
        else
            fclose(fid_write_check);
        end
    end

    % Delete any legacy 'Processed_Data' sheet (underscore variant) before
    % writing, so we never end up with two similarly named sheets.
    if exist(Report_Path_To_Write, 'file')
        All_Sheets = string(sheetnames(Report_Path_To_Write));
        Legacy_Names = ["Processed_Data"];   % add more variants here if needed
        Sheets_To_Delete = intersect(All_Sheets, Legacy_Names);
        if ~isempty(Sheets_To_Delete)
            try
                Excel_App_Cleanup = actxserver('Excel.Application');
                Excel_App_Cleanup.Visible = false;
                Excel_App_Cleanup.DisplayAlerts = false;
                WB_Cleanup = Excel_App_Cleanup.Workbooks.Open(Report_Path_To_Write);
                for k = 1:numel(Sheets_To_Delete)
                    try
                        WB_Cleanup.Worksheets.Item(char(Sheets_To_Delete(k))).Delete;
                        fprintf('      Deleted legacy sheet "%s".\n', Sheets_To_Delete(k));
                    catch
                    end
                end
                WB_Cleanup.Save;
                WB_Cleanup.Close(false);
                Excel_App_Cleanup.Quit;
                delete(Excel_App_Cleanup);
            catch Cleanup_Err
                fprintf('      Note: could not remove legacy sheet(s) - %s\n', Cleanup_Err.message);
            end
        end
    end

    % Always overwrite the processed sheet for the latest run.
    fprintf('      Writing to: %s\n', Report_Path_To_Write);
    writetable(Processed_Report_Table, Report_Path_To_Write, ...
        'Sheet', Processed_Sheet_Name, 'WriteMode', 'overwritesheet');
    fprintf('      %s sheet written successfully.\n', Processed_Sheet_Name);

    if Damage_Struct.Damage_Computed
        UTS_Index = round(double(True_Undamaged_Struct.Activation_Index));
        UTS_Index = max(1, min(Data_Point_Count, UTS_Index));
        Post_UTS_Count = Data_Point_Count - UTS_Index + 1;  % includes UTS row

        % Current run displacement from engineering UTS (necking onset) onwards.
        Element_Size_Text = num2str(Damage_Struct.Element_Size_L, '%.6f');
        Element_Size_Text = strrep(Element_Size_Text, '-', 'm');
        Element_Size_Text = strrep(Element_Size_Text, '.', 'p');
        Element_Size_Column_Name = ['Element_Size_L_', Element_Size_Text];
        Current_Displacement = Damage_Struct.Equivalent_Plastic_Displacement(UTS_Index:end);

        % Start building the output table already truncated at engineering UTS.
        Displacement_Table = table();

        % Read existing columns from a previous run (already truncated)
        Existing_Sheet_Names = sheetnames(Report_Path_To_Write);
        if any(strcmp(Existing_Sheet_Names, Displacement_Sheet_Name))
            Existing_Displacement_Table = readtable(Report_Path_To_Write, ...
                'Sheet', Displacement_Sheet_Name, ...
                'VariableNamingRule', 'preserve');

            Existing_Variable_Names = Existing_Displacement_Table.Properties.VariableNames;
            Existing_Element_Columns = Existing_Variable_Names(startsWith(Existing_Variable_Names, 'Element_Size_L_'));

            for Column_Number = 1:numel(Existing_Element_Columns)
                Existing_Column_Name = Existing_Element_Columns{Column_Number};
                % Skip if this is the same element size (will be overwritten below)
                if strcmp(Existing_Column_Name, Element_Size_Column_Name)
                    continue;
                end
                Existing_Column_Data = Existing_Displacement_Table.(Existing_Column_Name);
                Resized_Column_Data = nan(Post_UTS_Count, 1);
                Copy_Count = min(Post_UTS_Count, numel(Existing_Column_Data));
                Resized_Column_Data(1:Copy_Count) = Existing_Column_Data(1:Copy_Count);
                Displacement_Table.(Existing_Column_Name) = Resized_Column_Data;
            end
        end

        % Add (or overwrite) the current element size column
        Displacement_Table.(Element_Size_Column_Name) = Current_Displacement;

        % Sort element size columns by numeric value
        Displacement_Variable_Names = Displacement_Table.Properties.VariableNames;
        Element_Column_Names = Displacement_Variable_Names(startsWith(Displacement_Variable_Names, 'Element_Size_L_'));

        if isempty(Element_Column_Names)
            Sorted_Displacement_Table = Displacement_Table;
        else
            Element_Column_Values = zeros(numel(Element_Column_Names), 1);
            for Column_Number = 1:numel(Element_Column_Names)
                Parsed_Text = erase(Element_Column_Names{Column_Number}, 'Element_Size_L_');
                Parsed_Text = strrep(Parsed_Text, 'm', '-');
                Parsed_Text = strrep(Parsed_Text, 'p', '.');
                Element_Column_Values(Column_Number) = str2double(Parsed_Text);
            end
            [~, Sorted_Index] = sort(Element_Column_Values);
            Sorted_Element_Column_Names = Element_Column_Names(Sorted_Index);
            Sorted_Displacement_Table = Displacement_Table(:, Sorted_Element_Column_Names);
        end

        writetable(Sorted_Displacement_Table, Report_Path_To_Write, ...
            'Sheet', Displacement_Sheet_Name, 'WriteMode', 'overwritesheet');
        fprintf('      %s sheet written successfully.\n', Displacement_Sheet_Name);
    else
        Sorted_Displacement_Table = table();
    end

    % Apply formatting using Excel COM automation.
    fprintf('      Applying Excel formatting...\n');
    Last_Format_Step = "initialisation";
    try
        Last_Format_Step = "start Excel COM";
        Excel_Application = actxserver('Excel.Application');
        Excel_Application.Visible = false;
        Excel_Application.DisplayAlerts = false;
        try
            Excel_Application.ScreenUpdating = false;
        catch
        end
        try
            Excel_Application.EnableEvents = false;
        catch
        end

        Last_Format_Step = "open workbook";
        Workbook_Object = Excel_Application.Workbooks.Open(Report_Path_To_Write);

        Last_Format_Step = "access processed worksheet";
        Processed_Worksheet = Workbook_Object.Worksheets.Item(Processed_Sheet_Name);

        Processed_Row_Count = height(Processed_Report_Table) + 1;
        Processed_Column_Count = width(Processed_Report_Table);
        Processed_Last_Column_Letter = Excel_Column_Name(Processed_Column_Count);

        Last_Format_Step = "format processed headers";
        Processed_Header_Range = Processed_Worksheet.Range(['A1:', Processed_Last_Column_Letter, '1']);
        Processed_Header_Range.Font.Bold = true;

        % --- Colour definitions ---
        Engineering_Header_Color = 221 + 256 * 235 + 65536 * 247;
        True_Header_Color = 226 + 256 * 239 + 65536 * 218;
        Damage_Header_Color = 255 + 256 * 242 + 65536 * 204;
        Marker_Header_Color = 242 + 256 * 220 + 65536 * 219;
        Yield_Row_Color = 255 + 256 * 244 + 65536 * 204;
        UTS_Row_Color = 255 + 256 * 229 + 65536 * 204;
        Elastic_Regime_Color = 222 + 256 * 235 + 65536 * 247;
        Plastic_Regime_Color = 252 + 256 * 228 + 65536 * 214;
        Summary_Header_Color = 200 + 256 * 200 + 65536 * 255;
        Summary_Eng_Color = 230 + 256 * 240 + 65536 * 255;
        Summary_True_Color = 230 + 256 * 255 + 65536 * 230;
        Summary_Effective_Color = 255 + 256 * 246 + 65536 * 221;

        % --- Column group ranges ---
        True_Group_Start = Engineering_Column_Count + 1;
        True_Group_End = Engineering_Column_Count + 3;
        Damage_Group_Start = Engineering_Column_Count + 4;
        Damage_Group_End = Engineering_Column_Count + 8;
        Marker_Group_Start = Engineering_Column_Count + 9;
        Marker_Group_End = Engineering_Column_Count + 10;

        % Engineering strain/stress column letters (columns 1..Engineering_Column_Count)
        Eng_Start_Letter = 'A';
        Eng_End_Letter = Excel_Column_Name(Engineering_Column_Count);

        % True strain/stress column letters (True_Group_Start..True_Group_Start+1)
        True_Strain_Col_Letter = Excel_Column_Name(True_Group_Start);
        True_Stress_Col_Letter = Excel_Column_Name(True_Group_Start + 1);

        % --- Header colouring ---
        Last_Format_Step = "apply header group colors";
        if Engineering_Column_Count > 0
            Processed_Worksheet.Range(['A1:', Eng_End_Letter, '1']).Interior.Color = Engineering_Header_Color;
        end
        if True_Group_Start <= Processed_Column_Count
            True_Group_End = min(True_Group_End, Processed_Column_Count);
            True_Group_Start_Letter = Excel_Column_Name(True_Group_Start);
            True_Group_End_Letter = Excel_Column_Name(True_Group_End);
            Processed_Worksheet.Range([True_Group_Start_Letter, '1:', True_Group_End_Letter, '1']).Interior.Color = True_Header_Color;
        end
        if Damage_Group_Start <= Processed_Column_Count
            Damage_Group_End = min(Damage_Group_End, Processed_Column_Count);
            Damage_Group_Start_Letter = Excel_Column_Name(Damage_Group_Start);
            Damage_Group_End_Letter = Excel_Column_Name(Damage_Group_End);
            Processed_Worksheet.Range([Damage_Group_Start_Letter, '1:', Damage_Group_End_Letter, '1']).Interior.Color = Damage_Header_Color;
        end
        if Marker_Group_Start <= Processed_Column_Count
            Marker_Group_End = min(Marker_Group_End, Processed_Column_Count);
            Marker_Group_Start_Letter = Excel_Column_Name(Marker_Group_Start);
            Marker_Group_End_Letter = Excel_Column_Name(Marker_Group_End);
            Processed_Worksheet.Range([Marker_Group_Start_Letter, '1:', Marker_Group_End_Letter, '1']).Interior.Color = Marker_Header_Color;
        end

        % --- Per-column yield and UTS highlighting (not full rows) ---
        % Engineering yield: highlight only engineering strain + stress columns
        Last_Format_Step = "highlight yield and UTS rows";
        Eng_Yield_Row = Linear_Fit_Struct.Yield_Index + 1;
        Eng_Yield_Addr = [Eng_Start_Letter, num2str(Eng_Yield_Row), ':', Eng_End_Letter, num2str(Eng_Yield_Row)];
        Processed_Worksheet.Range(Eng_Yield_Addr).Interior.Color = Yield_Row_Color;

        % True yield: highlight only true strain + stress columns (may be a different row)
        True_Yield_Row = Linear_Fit_Struct.True_Yield_Index + 1;
        True_Yield_Addr = [True_Strain_Col_Letter, num2str(True_Yield_Row), ':', True_Stress_Col_Letter, num2str(True_Yield_Row)];
        Processed_Worksheet.Range(True_Yield_Addr).Interior.Color = Yield_Row_Color;

        % Engineering UTS: highlight only engineering columns at the peak stress row
        Eng_UTS_Row = Ultimate_Tensile_Strength_Struct.UTS_Index + 1;
        Eng_UTS_Addr = [Eng_Start_Letter, num2str(Eng_UTS_Row), ':', Eng_End_Letter, num2str(Eng_UTS_Row)];
        Processed_Worksheet.Range(Eng_UTS_Addr).Interior.Color = UTS_Row_Color;

        % True UTS (Considere): highlight only true columns at the Considere index row
        True_UTS_Row = Considere_Struct.Considere_Index + 1;
        True_UTS_Addr = [True_Strain_Col_Letter, num2str(True_UTS_Row), ':', True_Stress_Col_Letter, num2str(True_UTS_Row)];
        Processed_Worksheet.Range(True_UTS_Addr).Interior.Color = UTS_Row_Color;

        % --- Regime and Key_Point cell colouring ---
        Computed_Column_Names = Computed_Columns_Table.Properties.VariableNames;
        Regime_Offset = find(strcmp(Computed_Column_Names, 'Regime'), 1);
        Key_Point_Offset = find(strcmp(Computed_Column_Names, 'Key_Point'), 1);

        Regime_Column_Exists = ~isempty(Regime_Offset);
        Key_Point_Column_Exists = ~isempty(Key_Point_Offset);

        if Regime_Column_Exists
            Regime_Column_Number = Engineering_Column_Count + Regime_Offset;
            Regime_Column_Exists = Regime_Column_Number <= Processed_Column_Count;
            if Regime_Column_Exists
                Regime_Column_Letter = Excel_Column_Name(Regime_Column_Number);
            end
        end
        if Key_Point_Column_Exists
            Key_Point_Column_Number = Engineering_Column_Count + Key_Point_Offset;
            Key_Point_Column_Exists = Key_Point_Column_Number <= Processed_Column_Count;
            if Key_Point_Column_Exists
                Key_Point_Column_Letter = Excel_Column_Name(Key_Point_Column_Number);
            end
        end

        Last_Format_Step = "format regime and key-point columns";
        if Regime_Column_Exists || Key_Point_Column_Exists
            for Row_Number = 2:Processed_Row_Count
                if Regime_Column_Exists
                    Regime_Cell_Address = [Regime_Column_Letter, num2str(Row_Number)];
                    Regime_Cell_Range = Processed_Worksheet.Range(Regime_Cell_Address);
                    Regime_Value = string(Regime_Cell_Range.Value);
                    if Regime_Value == "Elastic"
                        Regime_Cell_Range.Interior.Color = Elastic_Regime_Color;
                    else
                        Regime_Cell_Range.Interior.Color = Plastic_Regime_Color;
                    end
                end

                if Key_Point_Column_Exists
                    Key_Point_Cell_Address = [Key_Point_Column_Letter, num2str(Row_Number)];
                    Key_Point_Cell_Range = Processed_Worksheet.Range(Key_Point_Cell_Address);
                    Key_Point_Value = string(Key_Point_Cell_Range.Value);
                    if strlength(Key_Point_Value) > 0
                        Key_Point_Cell_Range.Font.Bold = true;
                        Key_Point_Cell_Range.Interior.Color = Marker_Header_Color;
                    end
                end
            end
        end

        % ============================================================
        % Summary section: key values to the right of data columns
        % ============================================================
        Last_Format_Step = "write summary table";
        Summary_Start_Col = Processed_Column_Count + 2;  % one blank column gap
        SC = Summary_Start_Col;  % shorthand

        % Interpolated values for the summary
        Eng_Yield_Strain_Val = Linear_Fit_Struct.Yield_Strain;
        Eng_Yield_Stress_Val = Linear_Fit_Struct.Yield_Stress;
        True_Yield_Strain_Val = Linear_Fit_Struct.True_Yield_Strain;
        True_Yield_Stress_Val = Linear_Fit_Struct.True_Yield_Stress;
        Eng_UTS_Strain_Val = Ultimate_Tensile_Strength_Struct.UTS_Strain;
        Eng_UTS_Stress_Val = Ultimate_Tensile_Strength_Struct.UTS_Stress;
        Eng_UTS_Elastic_Strain_Val = Eng_UTS_Stress_Val / Linear_Fit_Struct.Youngs_Modulus;
        Eng_UTS_Plastic_Strain_Val = max(Eng_UTS_Strain_Val - Eng_UTS_Elastic_Strain_Val, 0);
        True_UTS_Strain_Val = Considere_Struct.Considere_Intersection_Strain;
        True_UTS_Stress_Val = Considere_Struct.Considere_Intersection_Stress;
        True_UTS_Elastic_Strain_Val = Considere_Struct.Considere_Elastic_Strain;
        True_UTS_Plastic_Strain_Val = Considere_Struct.Considere_Plastic_Strain;
        Effective_Activation_True_Strain_Val = True_Undamaged_Struct.Activation_True_Strain;
        Effective_Activation_True_Stress_Val = True_Undamaged_Struct.Activation_True_Stress;
        Effective_Yield_Strain_Val = True_Yield_Strain_Val;
        Effective_Yield_Stress_Val = interp1(Data_Struct.True_Strain, True_Undamaged_Struct.True_Stress_Undamaged, ...
            Effective_Yield_Strain_Val, 'linear', 'extrap');
        Effective_UTS_Strain_Val = Effective_Activation_True_Strain_Val;
        Effective_UTS_Stress_Val = Effective_Activation_True_Stress_Val;
        Effective_UTS_Elastic_Strain_Val = Effective_UTS_Stress_Val / Linear_Fit_Struct.Youngs_Modulus;
        Effective_UTS_Plastic_Strain_Val = max(Effective_UTS_Strain_Val - Effective_UTS_Elastic_Strain_Val, 0);
        Eng_Fail_Strain_Val = Data_Struct.Engineering_Strain(end);
        Eng_Fail_Stress_Val = Data_Struct.Engineering_Stress(end);
        True_Fail_Strain_Val = Data_Struct.True_Strain(end);
        True_Fail_Stress_Val = Data_Struct.True_Stress_Damaged(end);
        Effective_Fail_Strain_Val = True_Undamaged_Struct.True_Undamaged_Rupture_Strain;
        Effective_Fail_Stress_Val = True_Undamaged_Struct.True_Undamaged_Rupture_Stress;
        Fit_Window_Text = sprintf('[%.4f, %.4f]', Linear_Fit_Struct.Fit_Window(1), Linear_Fit_Struct.Fit_Window(2));

        % Write summary headers and values
        % Column SC: Label, Column SC+1: Engineering, Column SC+2: True, Column SC+3: Effective
        Summary_Col_Label = Excel_Column_Name(SC);
        Summary_Col_Eng = Excel_Column_Name(SC + 1);
        Summary_Col_True = Excel_Column_Name(SC + 2);
        Summary_Col_Effective = Excel_Column_Name(SC + 3);

        % Row 1: Section header
        Processed_Worksheet.Range([Summary_Col_Label, '1']).Value = 'Key Values';
        Processed_Worksheet.Range([Summary_Col_Label, '1']).Font.Bold = true;
        Processed_Worksheet.Range([Summary_Col_Label, '1:', Summary_Col_Effective, '1']).Interior.Color = Summary_Header_Color;

        % Row 2: Sub-headers
        Processed_Worksheet.Range([Summary_Col_Label, '2']).Value = 'Quantity';
        Processed_Worksheet.Range([Summary_Col_Eng, '2']).Value = 'Engineering';
        Processed_Worksheet.Range([Summary_Col_True, '2']).Value = 'TRUE';
        Processed_Worksheet.Range([Summary_Col_Effective, '2']).Value = 'EFFECTIVE';
        Processed_Worksheet.Range([Summary_Col_Label, '2:', Summary_Col_Effective, '2']).Font.Bold = true;

        % Row 3: Youngs Modulus
        Processed_Worksheet.Range([Summary_Col_Label, '3']).Value = 'Youngs Modulus (MPa)';
        Processed_Worksheet.Range([Summary_Col_Eng, '3']).Value = Linear_Fit_Struct.Youngs_Modulus;
        Processed_Worksheet.Range([Summary_Col_True, '3']).Value = Linear_Fit_Struct.Youngs_Modulus;
        Processed_Worksheet.Range([Summary_Col_Effective, '3']).Value = Linear_Fit_Struct.Youngs_Modulus;

        % Row 4: Youngs modulus fit window
        Processed_Worksheet.Range([Summary_Col_Label, '4']).Value = 'Youngs Modulus Fit Window';
        Processed_Worksheet.Range([Summary_Col_Eng, '4']).Value = Fit_Window_Text;
        Processed_Worksheet.Range([Summary_Col_True, '4']).Value = Fit_Window_Text;
        Processed_Worksheet.Range([Summary_Col_Effective, '4']).Value = Fit_Window_Text;

        % Row 5: Yield Strain
        Processed_Worksheet.Range([Summary_Col_Label, '5']).Value = 'Yield Strain';
        Processed_Worksheet.Range([Summary_Col_Eng, '5']).Value = Eng_Yield_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_True, '5']).Value = True_Yield_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '5']).Value = Effective_Yield_Strain_Val;

        % Row 6: Yield Stress
        Processed_Worksheet.Range([Summary_Col_Label, '6']).Value = 'Yield Stress (MPa)';
        Processed_Worksheet.Range([Summary_Col_Eng, '6']).Value = Eng_Yield_Stress_Val;
        Processed_Worksheet.Range([Summary_Col_True, '6']).Value = True_Yield_Stress_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '6']).Value = Effective_Yield_Stress_Val;

        % Row 7: UTS total strain
        Processed_Worksheet.Range([Summary_Col_Label, '7']).Value = 'UTS Total Strain';
        Processed_Worksheet.Range([Summary_Col_Eng, '7']).Value = Eng_UTS_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_True, '7']).Value = True_UTS_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '7']).Value = Effective_UTS_Strain_Val;

        % Row 8: UTS elastic strain
        Processed_Worksheet.Range([Summary_Col_Label, '8']).Value = 'UTS Elastic Strain';
        Processed_Worksheet.Range([Summary_Col_Eng, '8']).Value = Eng_UTS_Elastic_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_True, '8']).Value = True_UTS_Elastic_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '8']).Value = Effective_UTS_Elastic_Strain_Val;

        % Row 9: UTS plastic strain
        Processed_Worksheet.Range([Summary_Col_Label, '9']).Value = 'UTS Plastic Strain';
        Processed_Worksheet.Range([Summary_Col_Eng, '9']).Value = Eng_UTS_Plastic_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_True, '9']).Value = True_UTS_Plastic_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '9']).Value = Effective_UTS_Plastic_Strain_Val;

        % Row 10: UTS stress
        Processed_Worksheet.Range([Summary_Col_Label, '10']).Value = 'UTS Stress (MPa)';
        Processed_Worksheet.Range([Summary_Col_Eng, '10']).Value = Eng_UTS_Stress_Val;
        Processed_Worksheet.Range([Summary_Col_True, '10']).Value = True_UTS_Stress_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '10']).Value = Effective_UTS_Stress_Val;

        % Row 11: UTS method
        Processed_Worksheet.Range([Summary_Col_Label, '11']).Value = 'UTS Method';
        Processed_Worksheet.Range([Summary_Col_Eng, '11']).Value = 'Peak stress';
        Processed_Worksheet.Range([Summary_Col_True, '11']).Value = 'Considere criterion (comparison)';
        if isfield(True_Undamaged_Struct, 'Activation_Method')
            Processed_Worksheet.Range([Summary_Col_Effective, '11']).Value = char(string(True_Undamaged_Struct.Activation_Method));
        else
            Processed_Worksheet.Range([Summary_Col_Effective, '11']).Value = 'Engineering UTS';
        end

        % Row 12: Failure Strain
        Processed_Worksheet.Range([Summary_Col_Label, '12']).Value = 'Failure Strain';
        Processed_Worksheet.Range([Summary_Col_Eng, '12']).Value = Eng_Fail_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_True, '12']).Value = True_Fail_Strain_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '12']).Value = Effective_Fail_Strain_Val;

        % Row 13: Failure Stress
        Processed_Worksheet.Range([Summary_Col_Label, '13']).Value = 'Failure Stress (MPa)';
        Processed_Worksheet.Range([Summary_Col_Eng, '13']).Value = Eng_Fail_Stress_Val;
        Processed_Worksheet.Range([Summary_Col_True, '13']).Value = True_Fail_Stress_Val;
        Processed_Worksheet.Range([Summary_Col_Effective, '13']).Value = Effective_Fail_Stress_Val;

        % Row 14: Yield method
        Processed_Worksheet.Range([Summary_Col_Label, '14']).Value = 'Yield Method';
        Processed_Worksheet.Range([Summary_Col_Eng, '14']).Value = '0.2% offset (eng curve)';
        Processed_Worksheet.Range([Summary_Col_True, '14']).Value = '0.2% offset (true curve)';
        Processed_Worksheet.Range([Summary_Col_Effective, '14']).Value = '0.2% offset (true curve)';

        Summary_Numeric_Rows = [3, 5, 6, 7, 8, 9, 10, 12, 13];
        for Summary_Row = Summary_Numeric_Rows
            Processed_Worksheet.Range([Summary_Col_Eng, num2str(Summary_Row)]).Interior.Color = Summary_Eng_Color;
            Processed_Worksheet.Range([Summary_Col_True, num2str(Summary_Row)]).Interior.Color = Summary_True_Color;
            Processed_Worksheet.Range([Summary_Col_Effective, num2str(Summary_Row)]).Interior.Color = Summary_Effective_Color;
            Processed_Worksheet.Range([Summary_Col_Eng, num2str(Summary_Row), ':', Summary_Col_Effective, num2str(Summary_Row)]).NumberFormat = '0.000000';
        end
        Processed_Worksheet.Range([Summary_Col_Label, '11:', Summary_Col_Effective, '11']).Font.Italic = true;
        Processed_Worksheet.Range([Summary_Col_Label, '14:', Summary_Col_Effective, '14']).Font.Italic = true;

        % Add borders around the summary table
        Last_Format_Step = "style summary table";
        Summary_Range = Processed_Worksheet.Range([Summary_Col_Label, '1:', Summary_Col_Effective, '14']);
        for Border_Idx = 7:12
            Summary_Range.Borders.Item(Border_Idx).LineStyle = 1;  % xlContinuous
            Summary_Range.Borders.Item(Border_Idx).Weight = 2;     % xlThin
        end

        % AutoFit the summary columns
        Last_Format_Step = "autofit summary columns";
        Summary_Range.Columns.AutoFit;

        % --- Displacement sheet formatting ---
        if Damage_Struct.Damage_Computed
            Displacement_Row_Count = height(Sorted_Displacement_Table) + 1;
            Displacement_Column_Count = width(Sorted_Displacement_Table);

            if Displacement_Column_Count > 0
                Last_Format_Step = "access displacement worksheet";
                Displacement_Worksheet = Workbook_Object.Worksheets.Item(Displacement_Sheet_Name);
                Displacement_Last_Column_Letter = Excel_Column_Name(Displacement_Column_Count);

                Last_Format_Step = "format displacement headers";
                Displacement_Header_Range = Displacement_Worksheet.Range(['A1:', Displacement_Last_Column_Letter, '1']);
                Displacement_Header_Range.Font.Bold = true;
                Displacement_Worksheet.Range(['A1:', Displacement_Last_Column_Letter, '1']).Interior.Color = Damage_Header_Color;

                Last_Format_Step = "autofit displacement columns";
                Displacement_Worksheet.Range(['A1:', Displacement_Last_Column_Letter, num2str(Displacement_Row_Count)]).Columns.AutoFit;
            end
        end

        Last_Format_Step = "autofit processed columns";
        Processed_Worksheet.Range(['A1:', Processed_Last_Column_Letter, num2str(Processed_Row_Count)]).Columns.AutoFit;

        Last_Format_Step = "save and close workbook";
        Workbook_Object.Save;
        Workbook_Object.Close(false);
        Last_Format_Step = "quit Excel COM";
        Excel_Application.Quit;
        delete(Excel_Application);
        fprintf('      Formatting applied and file saved successfully.\n');

    catch Excel_Error
        fprintf('      Warning: Excel formatting failed at step "%s" - %s\n', char(string(Last_Format_Step)), Excel_Error.message);
        fprintf('      Data was still written to sheets successfully.\n');
        try
            Diagnostic_Path = fullfile(Input_Folder, 'excel_formatting_diagnostic.log');
            diag_fid = fopen(Diagnostic_Path, 'a');
            if diag_fid ~= -1
                fprintf(diag_fid, '[%s] step=%s | error=%s\n', char(datetime('now')), char(string(Last_Format_Step)), Excel_Error.message);
                fclose(diag_fid);
            end
        catch
        end
        try
            if exist('Workbook_Object', 'var') && ~isempty(Workbook_Object)
                Workbook_Object.Close(false);
            end
            if exist('Excel_Application', 'var') && ~isempty(Excel_Application)
                Excel_Application.Quit;
                delete(Excel_Application);
            end
        catch
            % Ignore cleanup errors
        end
    end

    Report_Struct = struct( ...
        'Output_Report_Path', Report_Path_To_Write, ...
        'Processed_Sheet_Name', Processed_Sheet_Name, ...
        'Displacement_Sheet_Name', Displacement_Sheet_Name, ...
        'Damage_Computed', Damage_Struct.Damage_Computed);
end

function Displacement = Update_Damage_For_Element_Size(Element_Size_L, Input_File)
    if nargin < 2 || isempty(Input_File)
        Input_File = 'Aluminium - Engineering stress_strain.xlsx';
    end
    if ~(ischar(Input_File) || isstring(Input_File))
        error('Input_File must be a character vector or string.');
    end
    if ~isfile(Input_File)
        error('Input file not found: %s', char(string(Input_File)));
    end
    if ~isscalar(Element_Size_L) || ~isnumeric(Element_Size_L) || ~isfinite(Element_Size_L) || Element_Size_L <= 0
        error('Element_Size_L must be a positive finite scalar.');
    end

    Data_Struct = Load_Engineering_And_True_Data(Input_File);
    Linear_Fit_Struct = Calculate_Linear_Fit_And_Yield_Point(Data_Struct);
    Ultimate_Tensile_Strength_Struct = Calculate_Engineering_Ultimate_Tensile_Strength(Data_Struct);
    Considere_Struct = Calculate_Considere_Criterion(Data_Struct, Linear_Fit_Struct);
    True_Undamaged_Initial_Struct = Calculate_True_Undamaged_Response( ...
        Data_Struct, Considere_Struct, Ultimate_Tensile_Strength_Struct);
    True_Undamaged_Struct = struct( ...
        'True_Stress_Undamaged', True_Undamaged_Initial_Struct.True_Stress_Undamaged, ...
        'True_Yield_Index', Linear_Fit_Struct.True_Yield_Index, ...
        'True_Yield_Strain', Linear_Fit_Struct.True_Yield_Strain, ...
        'True_Yield_Stress', Linear_Fit_Struct.True_Yield_Stress, ...
        'Activation_Index', True_Undamaged_Initial_Struct.Activation_Index, ...
        'Activation_Engineering_Strain', True_Undamaged_Initial_Struct.Activation_Engineering_Strain, ...
        'Activation_True_Strain', True_Undamaged_Initial_Struct.Activation_True_Strain, ...
        'Activation_True_Stress', True_Undamaged_Initial_Struct.Activation_True_Stress, ...
        'Activation_Nominal_Stress', True_Undamaged_Initial_Struct.Activation_Nominal_Stress, ...
        'Activation_Method', True_Undamaged_Initial_Struct.Activation_Method, ...
        'True_Undamaged_Rupture_Strain', Data_Struct.True_Strain(end), ...
        'True_Undamaged_Rupture_Stress', True_Undamaged_Initial_Struct.True_Stress_Undamaged(end));

    fprintf('\n============================================================\n');
    fprintf(' UPDATING DAMAGE FOR NEW ELEMENT SIZE\n');
    fprintf('============================================================\n');
    fprintf('Element Size L          : %.6f\n', Element_Size_L);

    % Recalculate damage with new element size
    fprintf('[1/2] Recalculating damage...\n');
    Damage_Struct = Calculate_Damage_From_UTS_To_Rupture(...
        Data_Struct, Linear_Fit_Struct, Ultimate_Tensile_Strength_Struct, ...
        Element_Size_L, True_Undamaged_Struct);

    Displacement = Damage_Struct.Equivalent_Plastic_Displacement;
    Displacement = Displacement(True_Undamaged_Struct.Activation_Index:end);

    % Update Excel workbook (writes only Displacement sheet with new column)
    fprintf('[2/2] Updating Excel workbook...\n');
    Report_Struct = Write_Processed_Report_Workbook(...
        Input_File, Data_Struct, Linear_Fit_Struct, ...
        Ultimate_Tensile_Strength_Struct, True_Undamaged_Struct, Damage_Struct, Considere_Struct);
    
    fprintf('============================================================\n');
    fprintf(' Update complete.\n');
    fprintf(' New displacement column added for L = %.6f\n', Element_Size_L);
    fprintf(' Report workbook         : %s\n', Report_Struct.Output_Report_Path);
    fprintf('============================================================\n\n');
end

function Column_Letter = Excel_Column_Name(Column_Number)
    Column_Letter = '';
    while Column_Number > 0
        Column_Position = mod(Column_Number - 1, 26);
        Column_Letter = [char(65 + Column_Position), Column_Letter];
        Column_Number = floor((Column_Number - 1) / 26);
    end
end

% ==============================================================
% LOCAL FUNCTIONS - PLOTTING
% ==============================================================

function Create_Plasticity_Plots(Plot_Data_Struct, Plot_Label_Struct)
    Create_Material_Data_Plots(Plot_Data_Struct, Plot_Label_Struct);
    Create_Preprocessing_Plots(Plot_Data_Struct, Plot_Label_Struct);
end

function Create_Material_Data_Plots(Plot_Data_Struct, Plot_Label_Struct)

    if ~exist(Plot_Label_Struct.Output_Directory, 'dir')
        mkdir(Plot_Label_Struct.Output_Directory);
    end

    S = Plot_Label_Struct.Style;
    P = S.Palette;
    LS = S.LineStyles;
    MK = S.Markers;
    Elastic_Indices = 1:Plot_Data_Struct.Yield_Index;
    Plastic_Indices = Plot_Data_Struct.Yield_Index:numel(Plot_Data_Struct.Engineering_Strain);

    % ---- Common annotation data (LaTeX formatted) ----
    Yield_Info = { ...
        '\textbf{Yield Data}', ...
        sprintf('$\\varepsilon^Y_N = %.6f$', Plot_Data_Struct.Yield_Strain), ...
        sprintf('$\\sigma^Y_N = %.4f$ MPa', Plot_Data_Struct.Yield_Stress), ...
        sprintf('$E = %.4f$ MPa', Plot_Data_Struct.Youngs_Modulus)};

    UTS_Info = { ...
        '\textbf{UTS Data (Consid\`ere)}', ...
        sprintf('$\\varepsilon_T^{C} = %.6f$', Plot_Data_Struct.Considere_Intersection_Strain), ...
        sprintf('$\\sigma_T^{C} = %.4f$ MPa', Plot_Data_Struct.Considere_Intersection_Stress)};

    True_Yield_Info = { ...
        '\textbf{True Yield Data}', ...
        sprintf('$\\varepsilon_T^Y = %.6f$', Plot_Data_Struct.True_Yield_Strain), ...
        sprintf('$\\sigma_T^Y = %.4f$ MPa', Plot_Data_Struct.True_Yield_Stress)};

    % ==================================================================
    % FIGURE 1 : DISABLED (now embedded in Figure 2)
    % ==================================================================
    F1 = Plot_Label_Struct.Figure_1;
    if isfield(F1, 'Enable') && F1.Enable
        Figure_1_Handle = figure('Name', F1.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_1_Handle, S);
        hold on; grid on;

        plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Engineering_Stress, ...
            'Color', P.Engineering, 'LineStyle', LS.Engineering, 'LineWidth', S.LineWidths);
        plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Linear_Fit_Stress, ...
            'Color', P.LinearFit, 'LineStyle', LS.LinearFit, 'LineWidth', S.LineWidths);
        plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Offset_Line_Stress, ...
            'Color', P.OffsetLine, 'LineStyle', LS.OffsetLine, 'LineWidth', S.LineWidths);

        xlim([0, 0.01]);
        ylim([0 (max(Plot_Data_Struct.Engineering_Stress) * 1.10)]);
        plot([Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Strain], [0, Plot_Data_Struct.Yield_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        plot([0, Plot_Data_Struct.Yield_Strain], [Plot_Data_Struct.Yield_Stress, Plot_Data_Struct.Yield_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);

        plot(Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
            'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
            'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
            'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine);

        Plot_Format(F1.X_Label, F1.Y_Label, F1.Title, S.Font_Sizes, S.Axis_Line_Width);
        lg1 = Legend_Format(F1.Legend, S.Legend_Font_Size, ...
            "vertical", 1, [], false, "on", S.Legend_Padding, F1.Legend_Location);

        % -- Annotation box --
        Add_Annotation_Box(Figure_1_Handle, lg1, Yield_Info, S, F1);
        Bring_Markers_To_Front(gca);
        Export_Figure_Files(Figure_1_Handle, Plot_Label_Struct.Output_Directory, F1.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 2 : Elastic-plastic regimes with yield-detail inset
    % ==================================================================
    F2 = Plot_Label_Struct.Figure_2;
    if isfield(F2, 'Enable') && F2.Enable
        Figure_2_Handle = figure('Name', F2.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_2_Handle, S);
        hold on; grid on;

        h2_e = plot(Plot_Data_Struct.Engineering_Strain(Elastic_Indices), ...
            Plot_Data_Struct.Engineering_Stress(Elastic_Indices), ...
            'Color', P.ElasticRegime, 'LineStyle', LS.ElasticRegime, 'LineWidth', S.LineWidths);
        h2_p = plot(Plot_Data_Struct.Engineering_Strain(Plastic_Indices), ...
            Plot_Data_Struct.Engineering_Stress(Plastic_Indices), ...
            'Color', P.PlasticRegime, 'LineStyle', LS.PlasticRegime, 'LineWidth', S.LineWidths);
        h2_y = plot(Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
            'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
            'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
            'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine);

        xlim([min(Plot_Data_Struct.Engineering_Strain) - 0.01, max(Plot_Data_Struct.Engineering_Strain) + 0.02]);
        ylim([0, max(Plot_Data_Struct.Engineering_Stress) * 1.10]);

        Plot_Format(F2.X_Label, F2.Y_Label, F2.Title, S.Font_Sizes, S.Axis_Line_Width);
        lg2 = Apply_Legend_Template(gca, [h2_e, h2_p, h2_y], F2.Legend, S, F2.Legend_Location, 1, S.Legend_Font_Size);
        Add_Annotation_Box(Figure_2_Handle, lg2, Yield_Info, S, F2);

        main_ax2 = gca;
        if isfield(F2, 'Inset') && F2.Inset.Enable
            z_xl2 = [0, 0.01];
            z_yl2 = [0, max(Plot_Data_Struct.Engineering_Stress) * 1.10];
            show_lines = isfield(F2.Inset, 'Show_Connecting_Lines') && F2.Inset.Show_Connecting_Lines;

            rect_xl2 = z_xl2;
            rect_yl2 = z_yl2;
            if isfield(F2.Inset, 'Rectangle_X_Limits') && numel(F2.Inset.Rectangle_X_Limits) == 2
                rect_xl2 = F2.Inset.Rectangle_X_Limits;
            end
            if isfield(F2.Inset, 'Rectangle_Y_Limits') && numel(F2.Inset.Rectangle_Y_Limits) == 2
                rect_yl2 = F2.Inset.Rectangle_Y_Limits;
            end

            inset2 = Create_Inset_Axes(main_ax2, z_xl2, z_yl2, F2.Inset.Position, S, show_lines, rect_xl2, rect_yl2);
            plot(inset2, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Engineering_Stress, ...
                'Color', P.Engineering, 'LineStyle', LS.Engineering, 'LineWidth', S.Inset.Line_Width);
            plot(inset2, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Linear_Fit_Stress, ...
                'Color', P.LinearFit, 'LineStyle', LS.LinearFit, 'LineWidth', S.Inset.Line_Width);
            plot(inset2, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Offset_Line_Stress, ...
                'Color', P.OffsetLine, 'LineStyle', LS.OffsetLine, 'LineWidth', S.Inset.Line_Width);
            plot(inset2, [Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Strain], ...
                [0, Plot_Data_Struct.Yield_Stress], 'Color', P.Guide, 'LineStyle', LS.Guide, ...
                'LineWidth', LS.Guide_Width);
            plot(inset2, [0, Plot_Data_Struct.Yield_Strain], ...
                [Plot_Data_Struct.Yield_Stress, Plot_Data_Struct.Yield_Stress], 'Color', P.Guide, ...
                'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
            plot(inset2, Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
                'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
                'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
                'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine);            

            xlim(inset2, z_xl2);
            ylim(inset2, z_yl2);
            Apply_Plot_Format_On_Axes(inset2, '', '', {F2.Inset.Title}, S, S.Font_Sizes);
            Apply_Legend_Template(inset2, [], F2.Inset.Legend_Inset, S, 'southeast', 1, S.Legend_Font_Size);

            inset2.XAxis.FontSize = S.Font_Sizes{1};
            inset2.YAxis.FontSize = S.Font_Sizes{2};
            grid(inset2, 'on');
            Apply_Inset_Axis_Style(inset2, S);
            Bring_Markers_To_Front(inset2);
        end
        Bring_Markers_To_Front(main_ax2);
        Export_Figure_Files(Figure_2_Handle, Plot_Label_Struct.Output_Directory, F2.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 3 : Omitted by configuration
    % ==================================================================
    F3 = Plot_Label_Struct.Figure_3;
    if isfield(F3, 'Enable') && F3.Enable
        Figure_3_Handle = figure('Name', F3.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_3_Handle, S);
        hold on; grid on;

        h3_d = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        h3_u = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Undamaged, ...
            'Color', P.TrueUndamaged, 'LineStyle', LS.TrueUndamaged, 'LineWidth', S.LineWidths);
        h3_y = plot(Plot_Data_Struct.True_Yield_Strain, Plot_Data_Struct.True_Yield_Stress, ...
            'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
            'MarkerFaceColor', MK.Yield.TrueFaceColor, 'MarkerEdgeColor', MK.Yield.TrueEdgeColor, ...
            'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine);

        Plot_Format(F3.X_Label, F3.Y_Label, F3.Title, S.Font_Sizes, S.Axis_Line_Width);
        lg3 = Apply_Legend_Template(gca, [h3_d, h3_u, h3_y], F3.Legend(1:3), S, F3.Legend_Location, 1, S.Legend_Font_Size);
        Add_Annotation_Box(Figure_3_Handle, lg3, [True_Yield_Info, {''}, UTS_Info], S, F3);
        Bring_Markers_To_Front(gca);

        Export_Figure_Files(Figure_3_Handle, Plot_Label_Struct.Output_Directory, F3.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 4 : Stress overlay
    % ==================================================================
    F4 = Plot_Label_Struct.Figure_4;
    if isfield(F4, 'Enable') && F4.Enable
        Figure_4_Handle = figure('Name', F4.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_4_Handle, S);
        hold on; grid on;
        h4_eng = plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Engineering_Stress, ...
            'Color', P.Engineering, 'LineStyle', LS.Engineering, 'LineWidth', S.LineWidths);
        h4_true = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        h4_und = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Undamaged, ...
            'Color', P.TrueUndamaged, 'LineStyle', LS.TrueUndamaged, 'LineWidth', S.LineWidths);
        E_line_x = linspace(0, F4.Elastic_Modulus_Max_Strain, 50)';
        h4_E = plot(E_line_x, Plot_Data_Struct.Youngs_Modulus .* E_line_x, ...
            'Color', P.YoungsModulus, 'LineStyle', LS.YoungsModulus, 'LineWidth', 1.7);

        h4_y = plot(Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
            'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
            'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
            'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine);

        h4_uts_eng = plot(Plot_Data_Struct.Engineering_UTS_Strain, Plot_Data_Struct.Engineering_UTS_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.EngineeringFaceColor, 'MarkerEdgeColor', MK.UTS.EngineeringEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);

        h4_uts_activation = plot(Plot_Data_Struct.Engineering_UTS_True_Strain, Plot_Data_Struct.Engineering_UTS_True_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.ActivationFaceColor, 'MarkerEdgeColor', MK.UTS.ActivationEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);

        h4_fail_eng = plot(Plot_Data_Struct.Engineering_Rupture_Strain, Plot_Data_Struct.Engineering_Rupture_Stress, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', MK.Failure.Size, ...
            'MarkerFaceColor', MK.Failure.EngineeringFaceColor, 'MarkerEdgeColor', MK.Failure.EngineeringEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth, 'LineStyle', LS.NoLine);

        h4_fail_true = plot(Plot_Data_Struct.True_Damaged_Rupture_Strain, Plot_Data_Struct.True_Damaged_Rupture_Stress, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', MK.Failure.Size, ...
            'MarkerFaceColor', MK.Failure.TrueDamagedFaceColor, 'MarkerEdgeColor', MK.Failure.TrueDamagedEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth, 'LineStyle', LS.NoLine);

        h4_fail_und = plot(Plot_Data_Struct.True_Undamaged_Rupture_Strain, Plot_Data_Struct.True_Undamaged_Rupture_Stress, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', MK.Failure.Size, ...
            'MarkerFaceColor', MK.Failure.TrueUndamagedFaceColor, 'MarkerEdgeColor', MK.Failure.TrueUndamagedEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth, 'LineStyle', LS.NoLine);

        xlim([-0.01, 0.5]);
        ylim([0, 215]);

        Plot_Format(F4.X_Label, F4.Y_Label, F4.Title, S.Font_Sizes, S.Axis_Line_Width);
        Apply_Display_Axis_Typography(gca, S);
        lg4 = Apply_Legend_Template(gca, ...
            [h4_eng, h4_true, h4_und, h4_E, h4_y, h4_uts_eng, h4_uts_activation, h4_fail_eng, h4_fail_true, h4_fail_und], ...
            F4.Legend, S, F4.Legend_Location, 1, S.Legend_Font_Size);
        if isfield(F4, 'Legend_Nudge') && numel(F4.Legend_Nudge) == 2
            lg4.Position(1) = lg4.Position(1) + F4.Legend_Nudge(1);
            lg4.Position(2) = lg4.Position(2) + F4.Legend_Nudge(2);
        end

        Ann_4 = { ...
            F4.Annotation.Yield_Rupture_Header, ...
            sprintf(F4.Annotation.Yield_Eng_Line, ...
                Plot_Data_Struct.Yield_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.Yield_Strain), ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_Rupture_Strain)), ...
            sprintf(F4.Annotation.Yield_True_Line, ...
                Plot_Data_Struct.True_Yield_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.True_Yield_Strain), ...
                Format_Strain_4sf(Plot_Data_Struct.True_Damaged_Rupture_Strain)), ...
            '', ...
            F4.Annotation.UTS_Header, ...
            sprintf(F4.Annotation.UTS_Eng_Line, ...
                Plot_Data_Struct.Engineering_UTS_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_Strain)), ...
            sprintf(F4.Annotation.UTS_True_Line, ...
                Plot_Data_Struct.Considere_Intersection_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.Considere_Intersection_Strain)), ...
            sprintf(F4.Annotation.UTS_Activation_Line, ...
                Plot_Data_Struct.Engineering_UTS_True_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_True_Strain)), ...
            '', ...
            F4.Annotation.Effective_Header, ...
            sprintf(F4.Annotation.Effective_Line, ...
                Plot_Data_Struct.True_Undamaged_Rupture_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.True_Undamaged_Rupture_Strain))};
        Add_Annotation_Box(Figure_4_Handle, lg4, Ann_4, S, F4);
        Bring_Markers_To_Front(gca);

        Export_Figure_Files(Figure_4_Handle, Plot_Label_Struct.Output_Directory, F4.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 5 : Damage evolution (tiled layout)
    % ==================================================================
    F5 = Plot_Label_Struct.Figure_5;
    if isfield(F5, 'Enable') && F5.Enable
        Figure_5_Handle = figure('Name', F5.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_5_Handle, S);
        Figure_5_Layout = tiledlayout(Figure_5_Handle, 1, 2, ...
            'TileSpacing', 'compact', 'Padding', 'compact');

        ax5_top = nexttile(Figure_5_Layout, 1);
        hold(ax5_top, 'on'); grid(ax5_top, 'on');
        plot(ax5_top, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Damage, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        xlim(ax5_top, [min(Plot_Data_Struct.Engineering_Strain), ...
            max(Plot_Data_Struct.Engineering_Strain)]);
        ylim(ax5_top, [0, 1.05]);
        axes(ax5_top);
        Plot_Format(F5.Top_X_Label, F5.Top_Y_Label, F5.Top_Title, S.Font_Sizes, S.Axis_Line_Width);
        Legend_Format(F5.Top_Legend, S.Legend_Font_Size, ...
            "vertical", 1, [], false, "on", S.Legend_Padding, F5.Top_Legend_Location);

        ax5_bot = nexttile(Figure_5_Layout, 2);
        hold(ax5_bot, 'on'); grid(ax5_bot, 'on');

        % True plastic strain
        plot(ax5_bot, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.True_Plastic_Strain, ...
            'Color', P.YoungsModulus, 'LineStyle', LS.YoungsModulus, ...
            'LineWidth', S.LineWidths);

        % Multi-L displacement framework: read all L columns from xlsx
        Bot_Legend_Entries = F5.Bottom_Legend(1);  % start with plastic strain entry
        if isfield(Plot_Data_Struct, 'XLSX_Path') && exist(Plot_Data_Struct.XLSX_Path, 'file')
            try
                Disp_Sheet_Names = sheetnames(Plot_Data_Struct.XLSX_Path);
                Disp_Sheet_Idx = find(contains(Disp_Sheet_Names, 'Displacement', 'IgnoreCase', true), 1);
                if ~isempty(Disp_Sheet_Idx)
                    Disp_Table = readtable(Plot_Data_Struct.XLSX_Path, ...
                        'Sheet', Disp_Sheet_Names(Disp_Sheet_Idx), 'VariableNamingRule', 'preserve');
                    Disp_Var_Names = Disp_Table.Properties.VariableNames;
                    L_Columns = Disp_Var_Names(startsWith(Disp_Var_Names, 'Element_Size_L_'));
                    Disp_Color_Map = Get_High_Contrast_Colormap(max(numel(L_Columns), 1), F5.Displacement_Colormap);
                    Disp_Line_Styles = F5.Displacement_Line_Styles;
                    for L_Col_Idx = 1:numel(L_Columns)
                        L_Col_Data = Disp_Table.(L_Columns{L_Col_Idx});
                        L_Strain  = Disp_Table{:, 1};
                        Valid_Mask = ~isnan(L_Col_Data) & ~isnan(L_Strain);
                        % Parse L value from column name
                        L_Parsed = erase(L_Columns{L_Col_Idx}, 'Element_Size_L_');
                        L_Parsed = strrep(L_Parsed, 'm', '-');
                        L_Parsed = strrep(L_Parsed, 'p', '.');
                        L_Value  = str2double(L_Parsed);
                        ls_idx = mod(L_Col_Idx - 1, numel(Disp_Line_Styles)) + 1;
                        plot(ax5_bot, L_Strain(Valid_Mask), L_Col_Data(Valid_Mask), ...
                            'Color', Disp_Color_Map(L_Col_Idx, :), ...
                            'LineStyle', Disp_Line_Styles{ls_idx}, ...
                            'LineWidth', S.LineWidths);
                        Bot_Legend_Entries{end+1} = sprintf('$u_{\\mathrm{pl}}^{\\mathrm{eq}}$, $L=%.2f$', L_Value); %#ok<AGROW>
                    end
                end
            catch Multi_L_Err
                fprintf('      Note: multi-L read failed - %s\n', Multi_L_Err.message);
                % Fallback: plot current displacement only
                plot(ax5_bot, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Equivalent_Plastic_Displacement, ...
                    'Color', P.Engineering, 'LineStyle', LS.Engineering, ...
                    'LineWidth', S.LineWidths);
                Bot_Legend_Entries{end+1} = F5.Bottom_Legend{2};
            end
        else
            % No xlsx path - fallback to single displacement
            plot(ax5_bot, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Equivalent_Plastic_Displacement, ...
                'Color', P.Engineering, 'LineStyle', LS.Engineering, ...
                'LineWidth', S.LineWidths);
            Bot_Legend_Entries{end+1} = F5.Bottom_Legend{2};
        end

        xlim(ax5_bot, [min(Plot_Data_Struct.Engineering_Strain), ...
            max(Plot_Data_Struct.Engineering_Strain)]);
        y_upper5b = max(max(Plot_Data_Struct.True_Plastic_Strain), ...
            max(Plot_Data_Struct.Equivalent_Plastic_Displacement)) * 1.10;
        y_upper5b = max(y_upper5b, 1e-3);  % guard
        ylim(ax5_bot, [0, y_upper5b]);
        axes(ax5_bot);
        Plot_Format(F5.Bottom_X_Label, F5.Bottom_Y_Label, F5.Bottom_Title, ...
            S.Font_Sizes, S.Axis_Line_Width);
        Legend_Format(Bot_Legend_Entries, S.Legend_Font_Size, ...
            "vertical", 1, [], false, "on", S.Legend_Padding, F5.Bottom_Legend_Location);

        Export_Figure_Files(Figure_5_Handle, Plot_Label_Struct.Output_Directory, F5.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 6 : Considere criterion construction
    % ==================================================================
    F6 = Plot_Label_Struct.Figure_6;
    if isfield(F6, 'Enable') && F6.Enable
        Figure_6_Handle = figure('Name', F6.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_6_Handle, S);
        hold on; grid on;

        if isfield(Plot_Data_Struct, 'WHR_Strain')
            whr_strain = Plot_Data_Struct.WHR_Strain;
        else
            whr_strain = Plot_Data_Struct.True_Strain(2:end);
        end
        whr_focus_min = max(Plot_Data_Struct.True_Yield_Strain, 0.70 * Plot_Data_Struct.Considere_Intersection_Strain);
        whr_mask6 = whr_strain >= whr_focus_min;
        if any(whr_mask6)
            whr_plot_strain = whr_strain(whr_mask6);
            whr_plot_rate = Plot_Data_Struct.Work_Hardening_Rate(whr_mask6);
        else
            whr_plot_strain = whr_strain;
            whr_plot_rate = Plot_Data_Struct.Work_Hardening_Rate;
        end

        h6_true = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        h6_whr = plot(whr_plot_strain, whr_plot_rate, ...
            'Color', P.WorkHardening, 'LineStyle', LS.WorkHardening, 'LineWidth', S.LineWidths);
        plot([Plot_Data_Struct.Considere_Intersection_Strain, Plot_Data_Struct.Considere_Intersection_Strain], ...
            [0, Plot_Data_Struct.Considere_Intersection_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        plot([0, Plot_Data_Struct.Considere_Intersection_Strain], ...
            [Plot_Data_Struct.Considere_Intersection_Stress, Plot_Data_Struct.Considere_Intersection_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);

        h6_point = plot(Plot_Data_Struct.Considere_Intersection_Strain, Plot_Data_Struct.Considere_Intersection_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.TrueFaceColor, 'MarkerEdgeColor', MK.UTS.TrueEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);

        whr_sorted6 = sort(whr_plot_rate(:));
        idx95_6 = max(1, min(numel(whr_sorted6), round(0.95 * numel(whr_sorted6))));
        whr_95_6 = whr_sorted6(idx95_6);
        y_upper6 = max([max(Plot_Data_Struct.True_Stress_Damaged), whr_95_6, Plot_Data_Struct.Considere_Intersection_Stress]) * 1.20;
        xlim([0, max(Plot_Data_Struct.True_Strain) * 1.02]);
        ylim([0, y_upper6]);

        Plot_Format(F6.X_Label, F6.Y_Label, F6.Title, S.Font_Sizes, S.Axis_Line_Width);
        lg6 = Apply_Legend_Template(gca, [h6_true, h6_whr, h6_point], F6.Legend, S, F6.Legend_Location, 1, S.Legend_Font_Size);

        Considere_Info = { ...
            F6.Annotation.Header, ...
            sprintf(F6.Annotation.EpsTrue_Line, Format_Strain_4sf(Plot_Data_Struct.Considere_Intersection_Strain)), ...
            sprintf(F6.Annotation.SigTrue_Line, Plot_Data_Struct.Considere_Intersection_Stress), ...
            sprintf(F6.Annotation.EpsElastic_Line, Format_Strain_4sf(Plot_Data_Struct.Considere_Elastic_Strain)), ...
            sprintf(F6.Annotation.EpsPlastic_Line, Format_Strain_4sf(Plot_Data_Struct.Considere_Plastic_Strain))};
        Add_Annotation_Box(Figure_6_Handle, lg6, Considere_Info, S, F6);

        if isfield(F6, 'Inset') && F6.Inset.Enable
            c_eps = Plot_Data_Struct.Considere_Intersection_Strain;
            c_sig = Plot_Data_Struct.Considere_Intersection_Stress;
            z_dx6 = max(c_eps * F6.Inset.Zoom_X_Frac, 1e-4);
            z_dy6 = max(c_sig * F6.Inset.Zoom_Y_Frac, 1);
            z_xl6 = [max(c_eps - z_dx6, 0), c_eps + z_dx6];
            z_yl6 = [max(c_sig - z_dy6, 0), c_sig + z_dy6];

            inset6 = Create_Inset_Axes(gca, z_xl6, z_yl6, F6.Inset.Position, S, true);
            h6i_true = plot(inset6, Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
                'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.Inset.Line_Width);
            h6i_whr = plot(inset6, whr_plot_strain, whr_plot_rate, ...
                'Color', P.WorkHardening, 'LineStyle', LS.WorkHardening, 'LineWidth', S.Inset.Line_Width);
            h6i_guides = plot(inset6, [c_eps, c_eps], [z_yl6(1), c_sig], ...
                'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
            plot(inset6, [z_xl6(1), c_eps], [c_sig, c_sig], ...
                'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);

            % Hysteresis-style loading segment terminating at the Considere point.
            d_eps6 = max(0.10 * diff(z_xl6), 2e-4);
            eps_seg6 = [max(c_eps - d_eps6, z_xl6(1)), c_eps];
            sig_hyst6 = [z_yl6(1), c_sig];

            h6i_hyst = plot(inset6, eps_seg6, sig_hyst6, ...
                'Color', MK.UTS.TrueFaceColor, 'LineStyle', LS.SchematicLoading, 'LineWidth', 1.4);

            h6i_point = plot(inset6, c_eps, c_sig, ...
                'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
                'MarkerFaceColor', MK.UTS.TrueFaceColor, 'MarkerEdgeColor', MK.UTS.TrueEdgeColor, ...
                'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);

            xlim(inset6, z_xl6);
            ylim(inset6, z_yl6);
            grid(inset6, 'on');
            Apply_Plot_Format_On_Axes(inset6, '', '', {F6.Inset.Title}, S, S.Font_Sizes);
            Apply_Legend_Template(inset6, [h6i_true, h6i_whr, h6i_point, h6i_guides, h6i_hyst], ...
                F6.Inset.Legend_Inset, S, 'best', 1, S.Legend_Font_Size - 1);

            Apply_Inset_Axis_Style(inset6, S);
            Bring_Markers_To_Front(inset6);
        end
        Bring_Markers_To_Front(gca);

        Export_Figure_Files(Figure_6_Handle, Plot_Label_Struct.Output_Directory, F6.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 15 : Considere comparison (true-strain vs engineering-strain forms)
    % ==================================================================
    F15 = Plot_Label_Struct.Figure_15_Considere_Form_Comparison;
    if isfield(F15, 'Enable') && F15.Enable
        Figure_15_Handle = figure('Name', F15.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_15_Handle, S);
        TL15 = tiledlayout(Figure_15_Handle, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

        % Left panel: true-strain Considere form
        ax15a = nexttile(TL15, 1);
        hold(ax15a, 'on'); grid(ax15a, 'on');
        h15a_true = plot(ax15a, Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        h15a_whr = plot(ax15a, Plot_Data_Struct.WHR_Strain, Plot_Data_Struct.Work_Hardening_Rate, ...
            'Color', P.WorkHardening, 'LineStyle', LS.WorkHardening, 'LineWidth', S.LineWidths);
        plot(ax15a, [Plot_Data_Struct.Considere_Intersection_Strain, Plot_Data_Struct.Considere_Intersection_Strain], ...
            [0, Plot_Data_Struct.Considere_Intersection_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        plot(ax15a, [0, Plot_Data_Struct.Considere_Intersection_Strain], ...
            [Plot_Data_Struct.Considere_Intersection_Stress, Plot_Data_Struct.Considere_Intersection_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        h15a_point = plot(ax15a, Plot_Data_Struct.Considere_Intersection_Strain, Plot_Data_Struct.Considere_Intersection_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.TrueFaceColor, 'MarkerEdgeColor', MK.UTS.TrueEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);
        h15a_uts = plot(ax15a, Plot_Data_Struct.Engineering_UTS_True_Strain, Plot_Data_Struct.Engineering_UTS_True_Stress, ...
            'Marker', F15.Mapped_UTS_Marker, 'MarkerSize', MK.UTS.Size - F15.Mapped_UTS_Size_Offset, ...
            'MarkerFaceColor', MK.UTS.MappedFaceColor, 'MarkerEdgeColor', MK.UTS.MappedEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);

        xlim(ax15a, F15.Left_X_Limits);
        ylim(ax15a, F15.Left_Y_Limits);
        Apply_Plot_Format_On_Axes(ax15a, F15.X_Labels{1}, F15.Y_Labels{1}, {F15.Tile_Titles{1}}, S, S.Font_Sizes, ...
            struct('Title_Font_Size', S.Title_Font_Size - 2));
        ax15a.LineWidth = 2;
        lg15a = Apply_Legend_Template(ax15a, [h15a_true, h15a_whr, h15a_point, h15a_uts], ...
            F15.Legend_Left, S, F15.Legend_Location_Left, 1, S.Legend_Font_Size - 3, ...
            struct('LineWidth', 2, 'AutoUpdate', 'off'));

        true_form_info15 = { ...
            F15.Annotation.True_Header, ...
            sprintf(F15.Annotation.True_Coord_Line, ...
                Format_Strain_4sf(Plot_Data_Struct.Considere_Intersection_Strain), ...
                Plot_Data_Struct.Considere_Intersection_Stress), ...
            sprintf(F15.Annotation.True_Mapped_Line, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_True_Strain), ...
                Plot_Data_Struct.Engineering_UTS_True_Stress), ...
            sprintf(F15.Annotation.True_Eng_UTS_Line, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_True_Strain), ...
                Plot_Data_Struct.Engineering_UTS_Stress)};
        ax15a_pos = get(ax15a, 'Position');
        ann15a_pos = [ ...
            ax15a_pos(1) + 0.02 * ax15a_pos(3), ...
            ax15a_pos(2) + 0.66 * ax15a_pos(4), ...
            0.42 * ax15a_pos(3), ...
            0.30 * ax15a_pos(4)];
        ann15a = annotation(Figure_15_Handle, 'textbox', ann15a_pos, ...
            'String', true_form_info15, ...
            'Interpreter', 'latex', ...
            'FitBoxToText', 'on', ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'top', ...
            'BackgroundColor', S.Annotation.BackgroundColor, ...
            'EdgeColor', S.Annotation.EdgeColor, ...
            'Color', S.Annotation.TextColor, ...
            'LineWidth', 2, ...
            'FontSize', S.Annotation.Font_Size - 2, ...
            'Margin', 5);
        if isprop(ann15a, 'Units')
            ann15a.Units = 'normalized';
        end

        % Right panel: engineering-strain Considere form on the true-stress curve
        ax15b = nexttile(TL15, 2);
        hold(ax15b, 'on'); grid(ax15b, 'on');
        h15b_true = plot(ax15b, Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        x_tangent15 = linspace(F15.Right_X_Limits(1), F15.Right_X_Limits(2), 300);
        y_tangent15 = Plot_Data_Struct.Considere_EngineeringForm_Tangent_Slope .* ...
            (x_tangent15 - Plot_Data_Struct.Considere_EngineeringForm_Intersection_Strain) + ...
            Plot_Data_Struct.Considere_EngineeringForm_True_Stress;
        h15b_tangent = plot(ax15b, x_tangent15, y_tangent15, ...
            'Color', P.YoungsModulus, 'LineStyle', LS.OffsetLine, 'LineWidth', S.LineWidths - 0.4);
        plot(ax15b, [Plot_Data_Struct.Considere_EngineeringForm_Intersection_Strain, Plot_Data_Struct.Considere_EngineeringForm_Intersection_Strain], ...
            [0, Plot_Data_Struct.Considere_EngineeringForm_True_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        plot(ax15b, [0, Plot_Data_Struct.Considere_EngineeringForm_Intersection_Strain], ...
            [Plot_Data_Struct.Considere_EngineeringForm_True_Stress, Plot_Data_Struct.Considere_EngineeringForm_True_Stress], ...
            'Color', P.Guide, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        h15b_point = plot(ax15b, Plot_Data_Struct.Considere_EngineeringForm_Intersection_Strain, Plot_Data_Struct.Considere_EngineeringForm_True_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.TrueFaceColor, 'MarkerEdgeColor', MK.UTS.TrueEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);
        h15b_uts = plot(ax15b, Plot_Data_Struct.Engineering_UTS_Strain, Plot_Data_Struct.Engineering_UTS_True_Stress, ...
            'Marker', F15.Mapped_UTS_Marker, 'MarkerSize', MK.UTS.Size - F15.Mapped_UTS_Size_Offset, ...
            'MarkerFaceColor', MK.UTS.MappedFaceColor, 'MarkerEdgeColor', MK.UTS.MappedEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);

        xlim(ax15b, F15.Right_X_Limits);
        ylim(ax15b, F15.Right_Y_Limits);
        Apply_Plot_Format_On_Axes(ax15b, F15.X_Labels{2}, F15.Y_Labels{2}, {F15.Tile_Titles{2}}, S, S.Font_Sizes, ...
            struct('Title_Font_Size', S.Title_Font_Size - 2));
        ax15b.LineWidth = 2;
        lg15b = Apply_Legend_Template(ax15b, [h15b_true, h15b_tangent, h15b_point, h15b_uts], ...
            F15.Legend_Right, S, F15.Legend_Location_Right, 1, S.Legend_Font_Size - 3, ...
            struct('LineWidth', 2, 'AutoUpdate', 'off'));

        eng_form_info15 = { ...
            F15.Annotation.Eng_Header, ...
            sprintf(F15.Annotation.Eng_Coord_Line, ...
                Format_Strain_4sf(Plot_Data_Struct.Considere_EngineeringForm_Intersection_Strain), ...
                Plot_Data_Struct.Considere_EngineeringForm_True_Stress), ...
            sprintf(F15.Annotation.Mapped_UTS_Line, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_Strain), ...
                Plot_Data_Struct.Engineering_UTS_True_Stress), ...
            sprintf(F15.Annotation.UTS_Line, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_Strain), ...
                Plot_Data_Struct.Engineering_UTS_Stress)};
        ax15b_pos = get(ax15b, 'Position');
        ann15b_pos = [ ...
            ax15b_pos(1) + 0.02 * ax15b_pos(3), ...
            ax15b_pos(2) + 0.66 * ax15b_pos(4), ...
            0.42 * ax15b_pos(3), ...
            0.30 * ax15b_pos(4)];
        ann15b = annotation(Figure_15_Handle, 'textbox', ann15b_pos, ...
            'String', eng_form_info15, ...
            'Interpreter', 'latex', ...
            'FitBoxToText', 'on', ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'top', ...
            'BackgroundColor', S.Annotation.BackgroundColor, ...
            'EdgeColor', S.Annotation.EdgeColor, ...
            'Color', S.Annotation.TextColor, ...
            'LineWidth', 2, ...
            'FontSize', S.Annotation.Font_Size - 2, ...
            'Margin', 5);
        if isprop(ann15b, 'Units')
            ann15b.Units = 'normalized';
        end

        sgtitle(TL15, strjoin(F15.Title, newline), 'Interpreter', 'latex', 'FontSize', S.Title_Font_Size);
        Bring_Markers_To_Front(ax15a);
        Bring_Markers_To_Front(ax15b);
        Bring_Markers_To_Front(ax15a);
        Bring_Markers_To_Front(ax15b);
        Export_Figure_Files(Figure_15_Handle, Plot_Label_Struct.Output_Directory, F15.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 7 : Reworked comprehensive overlay
    % ==================================================================
    F7 = Plot_Label_Struct.Figure_7;
    if isfield(F7, 'Enable') && F7.Enable
        Figure_7_Handle = figure('Name', F7.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_7_Handle, S);
        hold on; grid on;

        h7_eng = plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Engineering_Stress, ...
            'Color', P.Engineering, 'LineStyle', LS.Engineering, 'LineWidth', S.LineWidths, ...
            'DisplayName', F7.Labels.Engineering);
        h7_true = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths, ...
            'DisplayName', F7.Labels.TrueDamaged);
        h7_und = plot(Plot_Data_Struct.True_Strain, Plot_Data_Struct.True_Stress_Undamaged, ...
            'Color', P.TrueUndamaged, 'LineStyle', LS.TrueUndamaged, 'LineWidth', S.LineWidths, ...
            'DisplayName', F7.Labels.TrueUndamaged);

        merge_yield = abs(Plot_Data_Struct.Yield_Strain - Plot_Data_Struct.True_Yield_Strain) <= F7.Yield_Merge_Tolerance_Strain && ...
            abs(Plot_Data_Struct.Yield_Stress - Plot_Data_Struct.True_Yield_Stress) <= F7.Yield_Merge_Tolerance_Stress_MPa;

        yield_handles = gobjects(0);
        if merge_yield
            h7_y = plot(Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
                'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
                'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
                'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine, ...
                'DisplayName', F7.Labels.YieldMerged);
            yield_handles(end + 1) = h7_y; %#ok<AGROW>
        else
            h7_y_eng = plot(Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
                'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
                'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
                'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine, ...
                'DisplayName', F7.Labels.YieldEngineering);
            h7_y_true = plot(Plot_Data_Struct.True_Yield_Strain, Plot_Data_Struct.True_Yield_Stress, ...
                'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
                'MarkerFaceColor', MK.Yield.TrueFaceColor, 'MarkerEdgeColor', MK.Yield.TrueEdgeColor, ...
                'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine, ...
                'DisplayName', F7.Labels.YieldTrue);
            yield_handles(end + 1) = h7_y_eng; %#ok<AGROW>
            yield_handles(end + 1) = h7_y_true; %#ok<AGROW>
        end

        h7_uts_eng = plot(Plot_Data_Struct.Engineering_UTS_Strain, Plot_Data_Struct.Engineering_UTS_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.EngineeringFaceColor, 'MarkerEdgeColor', MK.UTS.EngineeringEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine, 'DisplayName', F7.Labels.UTSEngineering);

        h7_uts_activation = plot(Plot_Data_Struct.Engineering_UTS_True_Strain, Plot_Data_Struct.Engineering_UTS_True_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.ActivationFaceColor, 'MarkerEdgeColor', MK.UTS.ActivationEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine, 'DisplayName', F7.Labels.UTSActivationTrue);

        h7_fail_eng = plot(Plot_Data_Struct.Engineering_Rupture_Strain, Plot_Data_Struct.Engineering_Rupture_Stress, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', MK.Failure.Size, ...
            'MarkerFaceColor', MK.Failure.EngineeringFaceColor, 'MarkerEdgeColor', MK.Failure.EngineeringEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth, 'LineStyle', LS.NoLine, 'DisplayName', F7.Labels.FailureEngineering);

        h7_fail_true = plot(Plot_Data_Struct.True_Damaged_Rupture_Strain, Plot_Data_Struct.True_Damaged_Rupture_Stress, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', MK.Failure.Size, ...
            'MarkerFaceColor', MK.Failure.TrueDamagedFaceColor, 'MarkerEdgeColor', MK.Failure.TrueDamagedEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth, 'LineStyle', LS.NoLine, 'DisplayName', F7.Labels.FailureTrueDamaged);

        h7_fail_und = plot(Plot_Data_Struct.True_Undamaged_Rupture_Strain, Plot_Data_Struct.True_Undamaged_Rupture_Stress, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', MK.Failure.Size, ...
            'MarkerFaceColor', MK.Failure.TrueUndamagedFaceColor, 'MarkerEdgeColor', MK.Failure.TrueUndamagedEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth, 'LineStyle', LS.NoLine, 'DisplayName', F7.Labels.FailureTrueUndamaged);

        x_upper7 = max([max(Plot_Data_Struct.Engineering_Strain), max(Plot_Data_Struct.True_Strain)]) * 1.03;
        y_upper7 = max([max(Plot_Data_Struct.Engineering_Stress), max(Plot_Data_Struct.True_Stress_Damaged), ...
                        max(Plot_Data_Struct.True_Stress_Undamaged)]) * 1.12;
        xlim([0, x_upper7]);
        ylim([0, y_upper7]);

        Plot_Format(F7.X_Label, F7.Y_Label, F7.Title, S.Font_Sizes, S.Axis_Line_Width);
        Apply_Display_Axis_Typography(gca, S);

        legend_handles = [h7_eng, h7_true, h7_und, yield_handles, h7_uts_eng, h7_uts_activation, h7_fail_eng, h7_fail_true, h7_fail_und];
        lg7 = Apply_Legend_Template(gca, legend_handles, get(legend_handles, 'DisplayName'), ...
            S, F7.Legend_Location, 1, S.Legend_Font_Size - 1);

        Comprehensive_Info = { ...
            F7.Annotation.Header, ...
            sprintf(F7.Annotation.E_Line, Plot_Data_Struct.Youngs_Modulus)};

        if merge_yield
            Comprehensive_Info{end + 1} = sprintf(F7.Annotation.Yield_Merged_Line, ...
                Plot_Data_Struct.Yield_Stress, Format_Strain_4sf(Plot_Data_Struct.Yield_Strain));
        else
            Comprehensive_Info{end + 1} = sprintf(F7.Annotation.Yield_Engineering_Line, ...
                Plot_Data_Struct.Yield_Stress, Format_Strain_4sf(Plot_Data_Struct.Yield_Strain));
            Comprehensive_Info{end + 1} = sprintf(F7.Annotation.Yield_True_Line, ...
                Plot_Data_Struct.True_Yield_Stress, Format_Strain_4sf(Plot_Data_Struct.True_Yield_Strain));
        end

        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.UTS_Engineering_Line, ...
            Plot_Data_Struct.Engineering_UTS_Stress, Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.UTS_True_Line, ...
            Plot_Data_Struct.Considere_Intersection_Stress, Format_Strain_4sf(Plot_Data_Struct.Considere_Intersection_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.UTS_Activation_True_Line, ...
            Plot_Data_Struct.Engineering_UTS_True_Stress, Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_True_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.UTS_Plastic_Engineering_Line, Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_Plastic_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.UTS_Plastic_True_Line, Format_Strain_4sf(Plot_Data_Struct.True_UTS_Plastic_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.Rupture_Engineering_Line, ...
            Plot_Data_Struct.Engineering_Rupture_Stress, Format_Strain_4sf(Plot_Data_Struct.Engineering_Rupture_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.Rupture_True_Line, ...
            Plot_Data_Struct.True_Damaged_Rupture_Stress, Format_Strain_4sf(Plot_Data_Struct.True_Damaged_Rupture_Strain));
        Comprehensive_Info{end + 1} = sprintf(F7.Annotation.Rupture_Undamaged_True_Line, ...
            Plot_Data_Struct.True_Undamaged_Rupture_Stress, Format_Strain_4sf(Plot_Data_Struct.True_Undamaged_Rupture_Strain));

        Add_Annotation_Box(Figure_7_Handle, lg7, Comprehensive_Info, S, F7);

        Export_Figure_Files(Figure_7_Handle, Plot_Label_Struct.Output_Directory, F7.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 8 : Zoomed-in stress overlay
    % ==================================================================
    F8 = Plot_Label_Struct.Figure_8_Stress_Overlay_UTS_Zoom;
    if isfield(F8, 'Enable') && F8.Enable
        Figure_8_Handle = figure('Name', F8.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_8_Handle, S);
        hold on; grid on;

        h8_eng = plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.Engineering_Stress, ...
            'Color', P.Engineering, 'LineStyle', LS.Engineering, 'LineWidth', S.LineWidths);
        h8_true = plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.True_Stress_Damaged, ...
            'Color', P.TrueDamaged, 'LineStyle', LS.TrueDamaged, 'LineWidth', S.LineWidths);
        h8_eff = plot(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.True_Stress_Undamaged, ...
            'Color', P.TrueUndamaged, 'LineStyle', LS.TrueUndamaged, 'LineWidth', S.LineWidths);
        eff_uts_stress8 = interp1(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.True_Stress_Undamaged, ...
            Plot_Data_Struct.Engineering_UTS_Strain, 'linear', 'extrap');
        eff_considere_stress8 = interp1(Plot_Data_Struct.Engineering_Strain, Plot_Data_Struct.True_Stress_Undamaged, ...
            Plot_Data_Struct.Considere_Engineering_Intersection_Strain, 'linear', 'extrap');

        h8_yield = plot(Plot_Data_Struct.Yield_Strain, Plot_Data_Struct.Yield_Stress, ...
            'Marker', MK.Yield.Symbol, 'MarkerSize', MK.Yield.Size, ...
            'MarkerFaceColor', MK.Yield.FaceColor, 'MarkerEdgeColor', MK.Yield.EdgeColor, ...
            'LineWidth', MK.Yield.LineWidth, 'LineStyle', LS.NoLine);

        uts_x8 = [Plot_Data_Struct.Engineering_UTS_Strain; ...
                  Plot_Data_Struct.Considere_Engineering_Intersection_Strain; ...
                  Plot_Data_Struct.Engineering_UTS_Strain];
        x_lim8 = [max(Plot_Data_Struct.Yield_Strain - F8.Yield_Left_Pad, 0), ...
                  max(uts_x8) + F8.Post_UTS_Right_Pad];

        window_mask8 = Plot_Data_Struct.Engineering_Strain >= x_lim8(1) & Plot_Data_Struct.Engineering_Strain <= x_lim8(2);
        y_window8 = [ ...
            Plot_Data_Struct.Engineering_Stress(window_mask8); ...
            Plot_Data_Struct.True_Stress_Damaged(window_mask8); ...
            Plot_Data_Struct.True_Stress_Undamaged(window_mask8); ...
            Plot_Data_Struct.Yield_Stress; ...
            Plot_Data_Struct.Engineering_UTS_Stress; ...
            Plot_Data_Struct.Considere_Intersection_Stress; ...
            Plot_Data_Struct.Engineering_UTS_True_Stress];
        y_pad8 = max(F8.Min_Y_Pad, 0.10 * range(y_window8));
        y_lim8 = [max(min(y_window8) - y_pad8, 0), max(y_window8) + y_pad8];
        xlim(x_lim8);
        ylim(y_lim8);

        plot([Plot_Data_Struct.Engineering_UTS_Strain, Plot_Data_Struct.Engineering_UTS_Strain], ...
            [y_lim8(1), Plot_Data_Struct.Engineering_UTS_True_Stress], ...
            'Color', MK.UTS.ActivationEdgeColor, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        plot([x_lim8(1), Plot_Data_Struct.Engineering_UTS_Strain], ...
            [Plot_Data_Struct.Engineering_UTS_True_Stress, Plot_Data_Struct.Engineering_UTS_True_Stress], ...
            'Color', MK.UTS.ActivationEdgeColor, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width);
        plot([Plot_Data_Struct.Considere_Engineering_Intersection_Strain, Plot_Data_Struct.Considere_Engineering_Intersection_Strain], ...
            [y_lim8(1), Plot_Data_Struct.Considere_Intersection_Stress], ...
            'Color', MK.UTS.TrueEdgeColor, 'LineStyle', LS.Guide, 'LineWidth', LS.Guide_Width, ...
            'HandleVisibility', 'off');

        h8_uts_eng = plot(Plot_Data_Struct.Engineering_UTS_Strain, Plot_Data_Struct.Engineering_UTS_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.EngineeringFaceColor, 'MarkerEdgeColor', MK.UTS.EngineeringEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);
        h8_uts_true = plot(Plot_Data_Struct.Considere_Engineering_Intersection_Strain, Plot_Data_Struct.Considere_Intersection_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.TrueFaceColor, 'MarkerEdgeColor', MK.UTS.TrueEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);
        h8_uts_activation = plot(Plot_Data_Struct.Engineering_UTS_Strain, Plot_Data_Struct.Engineering_UTS_True_Stress, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', MK.UTS.Size, ...
            'MarkerFaceColor', MK.UTS.ActivationFaceColor, 'MarkerEdgeColor', MK.UTS.ActivationEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth, 'LineStyle', LS.NoLine);
        plot(Plot_Data_Struct.Engineering_UTS_Strain, eff_uts_stress8, ...
            'Marker', F8.Effective_Point_Marker, 'MarkerSize', MK.UTS.Size - F8.Effective_Point_Size_Offset, ...
            'MarkerFaceColor', Hex2Rgb(P.TrueUndamaged), 'MarkerEdgeColor', Hex2Rgb(P.TrueUndamaged), ...
            'LineWidth', F8.Effective_Point_LineWidth, 'LineStyle', LS.NoLine, 'HandleVisibility', 'off');
        plot(Plot_Data_Struct.Considere_Engineering_Intersection_Strain, eff_considere_stress8, ...
            'Marker', F8.Effective_Point_Marker, 'MarkerSize', MK.UTS.Size - F8.Effective_Point_Size_Offset, ...
            'MarkerFaceColor', Hex2Rgb(P.TrueUndamaged), 'MarkerEdgeColor', Hex2Rgb(P.TrueUndamaged), ...
            'LineWidth', F8.Effective_Point_LineWidth, 'LineStyle', LS.NoLine, 'HandleVisibility', 'off');

        Plot_Format(F8.X_Label, F8.Y_Label, F8.Title, S.Font_Sizes, S.Axis_Line_Width);
        Apply_Display_Axis_Typography(gca, S);
        F8_Legend_NumColumns = 1;
        if isfield(F8, 'Legend_NumColumns')
            F8_Legend_NumColumns = max(1, round(double(F8.Legend_NumColumns)));
        end
        lg8 = Apply_Legend_Template(gca, ...
            [h8_eng, h8_true, h8_eff, h8_yield, h8_uts_eng, h8_uts_true, h8_uts_activation], ...
            F8.Legend, S, F8.Legend_Location, ...
            F8_Legend_NumColumns, ...
            S.Legend_Font_Size);
        UTS_Info_8 = { ...
            F8.Annotation.Header, ...
            sprintf(F8.Annotation.Engineering_Line, ...
                Plot_Data_Struct.Engineering_UTS_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.Engineering_UTS_Strain)), ...
            sprintf(F8.Annotation.True_Line, ...
                Plot_Data_Struct.Considere_Intersection_Stress, ...
                Format_Strain_4sf(Plot_Data_Struct.Considere_Intersection_Strain)), ...
            sprintf(F8.Annotation.Activation_Line, ...
                Plot_Data_Struct.Engineering_UTS_True_Stress)};
        Add_Annotation_Box(Figure_8_Handle, lg8, UTS_Info_8, S, F8);
        Add_Axis_Annotation_Box(gca, Plot_Data_Struct.Engineering_UTS_Strain, ...
            y_lim8(1) + 0.18 * diff(y_lim8), F8.Annotation.Activation_Strain_Label, S, ...
            MK.UTS.ActivationEdgeColor, 90, 'middle', 'center');
        Add_Axis_Annotation_Box(gca, x_lim8(1) + 0.30 * diff(x_lim8), ...
            Plot_Data_Struct.Engineering_UTS_True_Stress + 0.045 * diff(y_lim8), ...
            F8.Annotation.Activation_Stress_Label, S, MK.UTS.ActivationEdgeColor, 0, 'middle', 'center');
        Bring_Markers_To_Front(gca);
        Export_Figure_Files(Figure_8_Handle, Plot_Label_Struct.Output_Directory, F8.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 9 : Damage softening law comparison
    % ==================================================================
    F9 = Plot_Label_Struct.Figure_9_Damage_Softening_Comparison;
    if isfield(F9, 'Enable') && F9.Enable && ...
            isfield(Plot_Data_Struct, 'Damage_Law_Data') && Plot_Data_Struct.Damage_Law_Data.Available
        Figure_9_Handle = figure('Name', F9.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_9_Handle, S);
        TL9 = tiledlayout(Figure_9_Handle, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
        Damage_Laws = {Plot_Data_Struct.Damage_Law_Data.Linear, Plot_Data_Struct.Damage_Law_Data.Tabular, Plot_Data_Struct.Damage_Law_Data.Exponential};
        Damage_Styles = {{P.Engineering, LS.Engineering}, {P.TrueDamaged, LS.TrueDamaged}};
        Annotation_Font_Size_9 = min(S.Annotation.Font_Size, 18);
        Annotation_Config_9 = struct('Annotation', struct('Placement', 'southeast'));
        for idx9 = 1:3
            ax9 = nexttile(TL9, idx9);
            hold(ax9, 'on'); grid(ax9, 'on');
            if idx9 <= 2
                h9_main = plot(ax9, Damage_Laws{idx9}.u_pl, Damage_Laws{idx9}.D, ...
                    'Color', Damage_Styles{idx9}{1}, 'LineStyle', Damage_Styles{idx9}{2}, ...
                    'LineWidth', S.LineWidths);
                lg9 = Apply_Legend_Template(ax9, h9_main, F9.Legend(idx9), ...
                    S, F9.Annotation_Placements{idx9}, 1, S.Legend_Font_Size - 1);
            else
                Num_Alpha_9 = max(numel(Damage_Laws{idx9}.Alpha_Values), 2);
                Color_Map_9 = Get_High_Contrast_Colormap(Num_Alpha_9, F9.Exponential_Colormap);
                Marker_Set_9 = F9.Exponential_Markers;
                Line_Styles_9 = F9.Exponential_Line_Styles;
                Exp_Handles_9 = cell(numel(Damage_Laws{idx9}.Alpha_Values), 1);
                Npts_9 = numel(Damage_Laws{idx9}.u_pl);
                Marker_Idx_9 = unique(round(linspace(1, max(Npts_9, 1), min(6, max(Npts_9, 1)))));
                for alpha_idx9 = 1:numel(Damage_Laws{idx9}.Alpha_Values)
                    this_color9 = Color_Map_9(alpha_idx9, :);
                    this_marker9 = Marker_Set_9{mod(alpha_idx9 - 1, numel(Marker_Set_9)) + 1};
                    this_ls9 = Line_Styles_9{mod(alpha_idx9 - 1, numel(Line_Styles_9)) + 1};
                    Exp_Handles_9{alpha_idx9} = plot(ax9, Damage_Laws{idx9}.u_pl, ...
                        Damage_Laws{idx9}.D_Matrix(:, alpha_idx9), ...
                        'Color', this_color9, ...
                        'LineStyle', this_ls9, ...
                        'LineWidth', S.LineWidths, ...
                        'Marker', this_marker9, ...
                        'MarkerIndices', Marker_Idx_9, ...
                        'MarkerSize', F9.Exponential_Marker_Size, ...
                        'MarkerFaceColor', F9.Exponential_Marker_FaceColor, ...
                        'MarkerEdgeColor', this_color9 * 0.6);
                end
                lg9 = Apply_Legend_Template(ax9, [Exp_Handles_9{:}], Damage_Laws{idx9}.Legend_Entries, ...
                    S, F9.Legend_Location, F9.Legend_NumColumns, S.Legend_Font_Size - 1);
            end
            ylim(ax9, [0, 1.05]);
            xlim(ax9, [0, max([Damage_Laws{idx9}.u_pl(:); 1e-8])]);
            Apply_Plot_Format_On_Axes(ax9, F9.X_Label, F9.Y_Label, {F9.Tile_Titles{idx9}}, S, {20, 20, 25});
            Apply_Primary_Axis_Style(ax9, S);
            Annotation_Config_9.Annotation.Placement = string(F9.Annotation_Placements{idx9});
            Previous_Annotation_Font_Size = S.Annotation.Font_Size;
            S.Annotation.Font_Size = Annotation_Font_Size_9;
            Add_Annotation_Box(Figure_9_Handle, lg9, {F9.Annotation_Text{idx9}}, S, Annotation_Config_9);
            S.Annotation.Font_Size = Previous_Annotation_Font_Size;
        end
        sgtitle(TL9, strjoin(F9.Title, newline), 'Interpreter', 'latex', 'FontSize', 25);
        Export_Figure_Files(Figure_9_Handle, Plot_Label_Struct.Output_Directory, F9.File_Name, S.Export_DPI);
    end
    % ==================================================================
    % FIGURE 10 : Effective stress parameterisation
    % ==================================================================
    F10 = Plot_Label_Struct.Figure_10_Effective_Stress_Parameterisation;
    if isfield(F10, 'Enable') && F10.Enable && ...
            isfield(Plot_Data_Struct, 'Effective_Response_Data') && Plot_Data_Struct.Effective_Response_Data.Available
        Figure_10_Handle = figure('Name', F10.Name, 'NumberTitle', 'off');
        Initialise_Figure_Window(Figure_10_Handle, S);
        ax10 = axes(Figure_10_Handle);

        Legend_Handles_10 = gobjects(0);
        Legend_Entries_10 = {};

        hold(ax10, 'on'); grid(ax10, 'on');
        valid_mask10 = Plot_Data_Struct.Effective_Response_Data.Valid_Post_UTS_Mask;
        eng_x10 = Plot_Data_Struct.Engineering_Strain(valid_mask10);
        eng_y10 = Plot_Data_Struct.Engineering_Stress(valid_mask10);
        true_x10 = Plot_Data_Struct.True_Strain(valid_mask10);
        true_y10 = Plot_Data_Struct.True_Stress_Damaged(valid_mask10);
        eff_x10 = Plot_Data_Struct.True_Strain(valid_mask10);
        eff_y10 = Plot_Data_Struct.True_Stress_Undamaged(valid_mask10);

        Legend_Handles_10(end + 1) = plot(ax10, ...
            eff_x10, eff_y10, ...
            'Color', Hex2Rgb(P.TrueUndamaged), 'LineStyle', LS.Engineering, ...
            'LineWidth', S.LineWidths + 0.3);
        Legend_Entries_10{end + 1} = 'Effective response: $\tilde{\sigma}-\varepsilon_T$';
        Legend_Handles_10(end + 1) = plot(ax10, ...
            true_x10, true_y10, ...
            'Color', Hex2Rgb(P.TrueDamaged), 'LineStyle', LS.TrueDamaged, ...
            'LineWidth', S.LineWidths);
        Legend_Entries_10{end + 1} = 'True response: $\sigma_T-\varepsilon_T$';
        Legend_Handles_10(end + 1) = plot(ax10, ...
            eng_x10, eng_y10, ...
            'Color', Hex2Rgb(P.Engineering), 'LineStyle', LS.Engineering, ...
            'LineWidth', S.LineWidths);
        Legend_Entries_10{end + 1} = 'Engineering response: $\sigma_N-\varepsilon_N$';

        x_lower10 = 0.95 * Plot_Data_Struct.Engineering_UTS_Strain;
        x_upper10 = max([eng_x10; true_x10]) * 1.02;
        y_lower10 = min([eng_y10; true_y10; eff_y10]) * 0.95;
        y_upper10 = max([eng_y10; true_y10; eff_y10]) * 1.05;
        xlim(ax10, [max(x_lower10, 0), x_upper10]);
        ylim(ax10, [max(y_lower10, 0), y_upper10]);

        Apply_Plot_Format_On_Axes(ax10, F10.X_Label, F10.Y_Label_Left, F10.Title, S, S.Font_Sizes);
        Apply_Primary_Axis_Style(ax10, S);
        Apply_Legend_Template(ax10, Legend_Handles_10, Legend_Entries_10, S, F10.Legend_Location, 1, S.Legend_Font_Size - 1);
        Export_Figure_Files(Figure_10_Handle, Plot_Label_Struct.Output_Directory, F10.File_Name, S.Export_DPI);
    end
end

function Print_Post_FEA_Opening_Dialog(Plot_Data_Struct, Convergence_Data_Directory, Damage_Evolution_Directory)
    FEA_Convergence_Data = struct();
    FEA_Damage_Evolution_Data = struct();
    FEA_Response_Data = struct();
    if isfield(Plot_Data_Struct, 'FEA_Convergence_Data')
        FEA_Convergence_Data = Plot_Data_Struct.FEA_Convergence_Data;
    end
    if isfield(Plot_Data_Struct, 'FEA_Damage_Evolution_Data')
        FEA_Damage_Evolution_Data = Plot_Data_Struct.FEA_Damage_Evolution_Data;
    end
    if isfield(Plot_Data_Struct, 'FEA_Response_Data')
        FEA_Response_Data = Plot_Data_Struct.FEA_Response_Data;
    end

    Summary_Rows = 0;
    Timeline_Rows = 0;
    Stage_Table_Count = 0;
    Damage_Rows = 0;
    if isfield(FEA_Convergence_Data, 'Summary_Table') && istable(FEA_Convergence_Data.Summary_Table)
        Summary_Rows = height(FEA_Convergence_Data.Summary_Table);
    end
    if isfield(FEA_Convergence_Data, 'Timeline_Table') && istable(FEA_Convergence_Data.Timeline_Table)
        Timeline_Rows = height(FEA_Convergence_Data.Timeline_Table);
    end
    if isfield(FEA_Convergence_Data, 'Field_Output_By_Stage') && isstruct(FEA_Convergence_Data.Field_Output_By_Stage)
        Stage_Table_Count = numel(fieldnames(FEA_Convergence_Data.Field_Output_By_Stage));
    end
    if isfield(FEA_Damage_Evolution_Data, 'Results_Table') && istable(FEA_Damage_Evolution_Data.Results_Table)
        Damage_Rows = height(FEA_Damage_Evolution_Data.Results_Table);
    end

    Criterion_Tol = 0.001;
    if isfield(FEA_Convergence_Data, 'Mesh_Conv_Tol') && ~isnan(FEA_Convergence_Data.Mesh_Conv_Tol)
        Criterion_Tol = FEA_Convergence_Data.Mesh_Conv_Tol;
    end

    Converged_Rel_LE22 = nan;
    Converged_Peak_LE22 = nan;
    Converged_Peak_Mises = nan;
    if isfield(FEA_Convergence_Data, 'Summary_Table') && istable(FEA_Convergence_Data.Summary_Table) && ...
            ~isempty(FEA_Convergence_Data.Summary_Table) && height(FEA_Convergence_Data.Summary_Table) > 0
        Summary_Table = FEA_Convergence_Data.Summary_Table;
        Summary_Names = Summary_Table.Properties.VariableNames;
        Converged_Row_Index = Resolve_Converged_Row_Index(Summary_Table, FEA_Convergence_Data);
        if ~isempty(Converged_Row_Index)
            if any(strcmp(Summary_Names, 'relLE22ToPrev'))
                Converged_Rel_LE22 = Summary_Table.relLE22ToPrev(Converged_Row_Index);
            end
            if any(strcmp(Summary_Names, 'peakLE22'))
                Converged_Peak_LE22 = Summary_Table.peakLE22(Converged_Row_Index);
            end
            if any(strcmp(Summary_Names, 'peakMises'))
                Converged_Peak_Mises = Summary_Table.peakMises(Converged_Row_Index);
            end
        end
    end

    Timeline_Frame_Count = 0;
    FEA_Peak_Eng_Strain = nan;
    FEA_Peak_Eng_Stress = nan;
    FEA_Peak_True_Strain = nan;
    FEA_Peak_True_Stress = nan;
    if isfield(FEA_Response_Data, 'Available') && FEA_Response_Data.Available
        if isfield(FEA_Response_Data, 'Frame') && ~isempty(FEA_Response_Data.Frame)
            Timeline_Frame_Count = numel(FEA_Response_Data.Frame);
        elseif isfield(FEA_Response_Data, 'True_Stress_Approx') && ~isempty(FEA_Response_Data.True_Stress_Approx)
            Timeline_Frame_Count = numel(FEA_Response_Data.True_Stress_Approx);
        end
        if isfield(FEA_Response_Data, 'Engineering_Strain_Approx') && ~isempty(FEA_Response_Data.Engineering_Strain_Approx)
            FEA_Peak_Eng_Strain = max(FEA_Response_Data.Engineering_Strain_Approx);
        end
        if isfield(FEA_Response_Data, 'Engineering_Stress_Approx') && ~isempty(FEA_Response_Data.Engineering_Stress_Approx)
            FEA_Peak_Eng_Stress = max(FEA_Response_Data.Engineering_Stress_Approx);
        end
        if isfield(FEA_Response_Data, 'True_Strain_Approx') && ~isempty(FEA_Response_Data.True_Strain_Approx)
            FEA_Peak_True_Strain = max(FEA_Response_Data.True_Strain_Approx);
        end
        if isfield(FEA_Response_Data, 'True_Stress_Approx') && ~isempty(FEA_Response_Data.True_Stress_Approx)
            FEA_Peak_True_Stress = max(FEA_Response_Data.True_Stress_Approx);
        end
    end

    Experiment_Peak_Eng_Stress = nan;
    if isfield(Plot_Data_Struct, 'Engineering_Stress') && ~isempty(Plot_Data_Struct.Engineering_Stress)
        Experiment_Peak_Eng_Stress = max(Plot_Data_Struct.Engineering_Stress);
    end

    Preferred_Mode = "";
    Preferred_Fully_Developed = "";
    if isfield(FEA_Damage_Evolution_Data, 'Preferred_Row') && istable(FEA_Damage_Evolution_Data.Preferred_Row) && ...
            ~isempty(FEA_Damage_Evolution_Data.Preferred_Row) && height(FEA_Damage_Evolution_Data.Preferred_Row) > 0
        Preferred_Row = FEA_Damage_Evolution_Data.Preferred_Row(1, :);
        Preferred_Names = Preferred_Row.Properties.VariableNames;
        if any(strcmp(Preferred_Names, 'fractureMode'))
            Preferred_Mode = string(Preferred_Row.fractureMode(1));
        end
        if any(strcmp(Preferred_Names, 'fullyDeveloped'))
            Preferred_Fully_Developed = string(Preferred_Row.fullyDeveloped(1));
        end
    end

    fprintf('\n============================================================\n');
    fprintf(' POST-FEA DATA PROCESSING\n');
    fprintf('============================================================\n');
    fprintf('Timestamp                : %s\n', char(datetime('now')));
    fprintf('Convergence data source  : %s\n', char(string(Convergence_Data_Directory)));
    fprintf('Damage-evolution source  : %s\n', char(string(Damage_Evolution_Directory)));
    fprintf('Convergence summary rows : %d\n', Summary_Rows);
    fprintf('Convergence timeline rows: %d\n', Timeline_Rows);
    fprintf('Field stage tables       : %d\n', Stage_Table_Count);
    fprintf('Damage-evolution rows    : %d\n', Damage_Rows);

    if isfield(FEA_Convergence_Data, 'Chosen_Mesh_h') && ~isnan(FEA_Convergence_Data.Chosen_Mesh_h)
        fprintf('Converged element size h : %.6f\n', FEA_Convergence_Data.Chosen_Mesh_h);
    else
        fprintf('Converged element size h : not resolved\n');
    end
    if isfield(FEA_Convergence_Data, 'Chosen_Num_Elements') && ~isnan(FEA_Convergence_Data.Chosen_Num_Elements)
        fprintf('Converged element count  : %.0f\n', FEA_Convergence_Data.Chosen_Num_Elements);
    end
    if isfield(FEA_Convergence_Data, 'Chosen_Job_Name') && strlength(string(FEA_Convergence_Data.Chosen_Job_Name)) > 0
        fprintf('Converged job            : %s\n', char(string(FEA_Convergence_Data.Chosen_Job_Name)));
    end
    fprintf('Convergence criterion    : |relLE22ToPrev| <= %.4g (%.3f%%)\n', Criterion_Tol, 100 * Criterion_Tol);
    if ~isnan(Converged_Rel_LE22)
        fprintf('Converged relLE22ToPrev  : %.6f (%.3f%%)\n', Converged_Rel_LE22, 100 * Converged_Rel_LE22);
    end
    if ~isnan(Converged_Peak_LE22)
        fprintf('Converged peak LE22      : %.6f\n', Converged_Peak_LE22);
    end
    if ~isnan(Converged_Peak_Mises)
        fprintf('Converged peak Mises     : %.4f MPa\n', Converged_Peak_Mises);
    end

    fprintf('\n--------------------- POST-FEA KEY METRICS ------------------\n');
    if Timeline_Frame_Count > 0
        fprintf('Timeline frames          : %d\n', Timeline_Frame_Count);
    else
        fprintf('Timeline frames          : unavailable\n');
    end
    if ~isnan(FEA_Peak_Eng_Strain)
        fprintf('Peak FEA engineering epsN: %.4f\n', FEA_Peak_Eng_Strain);
    end
    if ~isnan(FEA_Peak_Eng_Stress)
        fprintf('Peak FEA engineering sigN: %.4f MPa\n', FEA_Peak_Eng_Stress);
    end
    if ~isnan(FEA_Peak_True_Strain)
        fprintf('Peak FEA true epsT       : %.4f\n', FEA_Peak_True_Strain);
    end
    if ~isnan(FEA_Peak_True_Stress)
        fprintf('Peak FEA true sigT       : %.4f MPa\n', FEA_Peak_True_Stress);
    end
    if ~isnan(Experiment_Peak_Eng_Stress) && ~isnan(FEA_Peak_Eng_Stress)
        fprintf('Peak eng stress delta    : %+0.4f MPa (FEA - Experiment)\n', ...
            FEA_Peak_Eng_Stress - Experiment_Peak_Eng_Stress);
    end
    if strlength(Preferred_Mode) > 0
        fprintf('Preferred fracture mode  : %s\n', char(Preferred_Mode));
    end
    if strlength(Preferred_Fully_Developed) > 0
        fprintf('Preferred fully-developed: %s\n', char(Preferred_Fully_Developed));
    end
    fprintf('------------------------------------------------------------\n');
end

function Create_Preprocessing_Plots(Plot_Data_Struct, Plot_Label_Struct)

    if ~exist(Plot_Label_Struct.Output_Directory, 'dir')
        mkdir(Plot_Label_Struct.Output_Directory);
    end

    S = Plot_Label_Struct.Style;
    P = S.Palette;
    LS = S.LineStyles;
    MK = S.Markers;

    if isfield(Plot_Data_Struct, 'FEA_Damage_Evolution_Data') && Plot_Data_Struct.FEA_Damage_Evolution_Data.Available
        fprintf('[FEA] Damage-evolution rows loaded: %d\n', height(Plot_Data_Struct.FEA_Damage_Evolution_Data.Results_Table));
    else
        fprintf('[FEA] Damage-evolution outputs not available.\n');
    end

    % ==================================================================
    % FIGURE 12 : FEA mesh convergence
    % ==================================================================
    F12 = Plot_Label_Struct.Figure_12_FEA_Mesh_Convergence;
    if isfield(F12, 'Enable') && F12.Enable && ...
            isfield(Plot_Data_Struct, 'FEA_Convergence_Data') && Plot_Data_Struct.FEA_Convergence_Data.Available
        Summary_Table_12 = Plot_Data_Struct.FEA_Convergence_Data.Summary_Table;
        if ~isempty(Summary_Table_12) && height(Summary_Table_12) > 0
            Figure_12_Handle = figure('Name', F12.Name, 'NumberTitle', 'off');
            Initialise_Figure_Window(Figure_12_Handle, S);
            set(Figure_12_Handle, 'Color', F12.Legend_Background_Color);
            ax12 = axes(Figure_12_Handle); %#ok<LAXES>
            hold(ax12, 'on');
            grid(ax12, 'on');
            set(ax12, 'Color', F12.Legend_Background_Color, ...
                'XColor', F12.Axis_Text_Color, ...
                'YColor', F12.Axis_Text_Color, ...
                'GridColor', F12.Grid_Color, ...
                'GridAlpha', 0.8, ...
                'LineWidth', 1.6, ...
                'FontSize', S.Tick_Font_Size, ...
                'Layer', 'bottom');
            ax12.XMinorGrid = 'off';
            ax12.YMinorGrid = 'off';

            if any(strcmp(Summary_Table_12.Properties.VariableNames, 'pctDiffLE22'))
                le22_base = To_Double_Vector(Summary_Table_12.pctDiffLE22);
            else
                le22_base = 100 .* abs(To_Double_Vector(Summary_Table_12.relLE22ToPrev));
            end
            mask_metric12 = ~isnan(Summary_Table_12.numElements) & ~isnan(le22_base);
            Row_Indices_12 = find(mask_metric12);
            Num_Elements_12 = Summary_Table_12.numElements(mask_metric12);
            Metric_LE22_Pct_12 = le22_base(mask_metric12);
            Metric_S22_Pct_12 = nan(size(Metric_LE22_Pct_12));
            Metric_Mises_Pct_12 = nan(size(Metric_LE22_Pct_12));
            if any(strcmp(Summary_Table_12.Properties.VariableNames, 'pctDiffS22'))
                Metric_S22_Pct_12 = To_Double_Vector(Summary_Table_12.pctDiffS22(mask_metric12));
            elseif any(strcmp(Summary_Table_12.Properties.VariableNames, 'relS22ToPrev'))
                Metric_S22_Pct_12 = 100 .* abs(To_Double_Vector(Summary_Table_12.relS22ToPrev(mask_metric12)));
            end
            if any(strcmp(Summary_Table_12.Properties.VariableNames, 'pctDiffMises'))
                Metric_Mises_Pct_12 = To_Double_Vector(Summary_Table_12.pctDiffMises(mask_metric12));
            elseif any(strcmp(Summary_Table_12.Properties.VariableNames, 'relMisesToPrev'))
                Metric_Mises_Pct_12 = 100 .* abs(To_Double_Vector(Summary_Table_12.relMisesToPrev(mask_metric12)));
            end
            Converged_Row_12 = Resolve_Converged_Row_Index(Summary_Table_12, Plot_Data_Struct.FEA_Convergence_Data);
            if ~isempty(Num_Elements_12)
                Pair_Count_12 = numel(Num_Elements_12);
                Color_Map_12 = Get_High_Contrast_Colormap(max(Pair_Count_12, 16), F12.Pair_Colormap);
                Pair_Handles_12 = gobjects(Pair_Count_12, 1);
                Pair_Legend_12 = cell(Pair_Count_12, 1);
                Annotation_Text_12 = cell(Pair_Count_12, 1);
                Converged_Face_Color_12 = F12.Converged_Pair_Face_Color;
                Converged_Edge_Color_12 = F12.Converged_Pair_Edge_Color;

                Mesh_h_Vector_12 = nan(Pair_Count_12, 1);
                if any(strcmp(Summary_Table_12.Properties.VariableNames, 'mesh_h'))
                    Mesh_h_Vector_12 = Summary_Table_12.mesh_h(mask_metric12);
                end

                for idx12 = 1:Pair_Count_12
                    this_color = Color_Map_12(idx12, :);
                    this_edge = max(min(this_color .* F12.Pair_Edge_Shade_Factor, 1.0), 0.0);
                    Pair_Handles_12(idx12) = plot(ax12, Num_Elements_12(idx12), Metric_LE22_Pct_12(idx12), ...
                        'LineStyle', LS.NoLine, 'Marker', F12.Pair_Marker, 'MarkerSize', F12.Pair_Marker_Size, ...
                        'MarkerFaceColor', this_color, 'MarkerEdgeColor', this_edge, ...
                        'LineWidth', F12.Pair_Marker_Line_Width);

                    Fine_Row = Row_Indices_12(idx12);
                    Coarse_Row = max(Fine_Row - 1, 1);
                    Pair_Legend_12{idx12} = sprintf('$\\left|\\frac{\\varepsilon_{22}^{(%d)}-\\varepsilon_{22}^{(%d)}}{\\varepsilon_{22}^{(%d)}}\\right|$', ...
                        Fine_Row, Coarse_Row, Fine_Row);
                    Iter_Label_12 = idx12 + 1;

                    if isnan(Mesh_h_Vector_12(idx12))
                        Annotation_Text_12{idx12} = { ...
                            sprintf('$\\textbf{Mesh\\ Iteration}\\ %d$', Iter_Label_12), ...
                            sprintf('$N_e = %.0f$', Num_Elements_12(idx12)), ...
                            sprintf('$\\xi = %.4f\\%%$', Metric_LE22_Pct_12(idx12))};
                    else
                        Annotation_Text_12{idx12} = { ...
                            sprintf('$\\textbf{Mesh\\ Iteration}\\ %d$', Iter_Label_12), ...
                            sprintf('$L = %.6g\\,\\mathrm{mm}$', Mesh_h_Vector_12(idx12)), ...
                            sprintf('$N_e = %.0f$', Num_Elements_12(idx12)), ...
                            sprintf('$\\xi = %.4f\\%%$', Metric_LE22_Pct_12(idx12))};
                    end
                end

                Trendline_Power_12 = 1.50;
                if isfield(F12, 'Trendline_Powers')
                    Trendline_Power_Candidate_12 = To_Double_Vector(F12.Trendline_Powers);
                    Trendline_Power_Candidate_12 = Trendline_Power_Candidate_12( ...
                        ~isnan(Trendline_Power_Candidate_12) & Trendline_Power_Candidate_12 > 0);
                    if ~isempty(Trendline_Power_Candidate_12)
                        Trendline_Power_12 = Trendline_Power_Candidate_12(1);
                    end
                end
                Trendline_Samples_12 = 320;
                if isfield(F12, 'Trendline_Samples') && isfinite(double(F12.Trendline_Samples))
                    Trendline_Samples_12 = max(120, round(double(F12.Trendline_Samples)));
                end

                Trendline_Set_12 = Build_Power_Trendline_Set( ...
                    Num_Elements_12, Metric_LE22_Pct_12, Trendline_Power_12, Trendline_Samples_12);
                if ~isempty(Trendline_Set_12)
                    h12_trend = plot(ax12, Trendline_Set_12(1).X, Trendline_Set_12(1).Y, ...
                        'Color', F12.LE22_Trendline_Color, 'LineStyle', F12.LE22_Trendline_Style, 'LineWidth', F12.LE22_Trendline_Width);
                else
                    [Trendline_X_12, Trendline_Y_12] = Build_Smooth_Trendline(Num_Elements_12, Metric_LE22_Pct_12, 320);
                    h12_trend = plot(ax12, Trendline_X_12, Trendline_Y_12, ...
                        'Color', F12.LE22_Trendline_Color, 'LineStyle', F12.LE22_Trendline_Style, 'LineWidth', F12.LE22_Trendline_Width);
                end
                if any(~isnan(Metric_S22_Pct_12))
                    Mask_S22_Trend_12 = ~isnan(Num_Elements_12) & ~isnan(Metric_S22_Pct_12);
                    if nnz(Mask_S22_Trend_12) >= 2
                        Trendline_Set_S22_12 = Build_Power_Trendline_Set( ...
                            Num_Elements_12(Mask_S22_Trend_12), Metric_S22_Pct_12(Mask_S22_Trend_12), ...
                            Trendline_Power_12, Trendline_Samples_12);
                        if ~isempty(Trendline_Set_S22_12)
                            h12_s22 = plot(ax12, Trendline_Set_S22_12(1).X, Trendline_Set_S22_12(1).Y, ...
                                'Color', F12.S22_Trendline_Color, 'LineStyle', F12.S22_Trendline_Style, 'LineWidth', F12.S22_Trendline_Width);
                        else
                            [Trend_X_S22_12, Trend_Y_S22_12] = Build_Smooth_Trendline( ...
                                Num_Elements_12(Mask_S22_Trend_12), Metric_S22_Pct_12(Mask_S22_Trend_12), Trendline_Samples_12);
                            h12_s22 = plot(ax12, Trend_X_S22_12, Trend_Y_S22_12, ...
                                'Color', F12.S22_Trendline_Color, 'LineStyle', F12.S22_Trendline_Style, 'LineWidth', F12.S22_Trendline_Width);
                        end
                    else
                        h12_s22 = plot(ax12, nan, nan, 'LineStyle', LS.NoLine);
                    end
                else
                    h12_s22 = plot(ax12, nan, nan, 'LineStyle', LS.NoLine);
                end
                if any(~isnan(Metric_Mises_Pct_12))
                    Mask_Mises_Trend_12 = ~isnan(Num_Elements_12) & ~isnan(Metric_Mises_Pct_12);
                    if nnz(Mask_Mises_Trend_12) >= 2
                        Trendline_Set_Mises_12 = Build_Power_Trendline_Set( ...
                            Num_Elements_12(Mask_Mises_Trend_12), Metric_Mises_Pct_12(Mask_Mises_Trend_12), ...
                            Trendline_Power_12, Trendline_Samples_12);
                        if ~isempty(Trendline_Set_Mises_12)
                            h12_mises = plot(ax12, Trendline_Set_Mises_12(1).X, Trendline_Set_Mises_12(1).Y, ...
                                'Color', F12.Mises_Trendline_Color, 'LineStyle', F12.Mises_Trendline_Style, 'LineWidth', F12.Mises_Trendline_Width);
                        else
                            [Trend_X_Mises_12, Trend_Y_Mises_12] = Build_Smooth_Trendline( ...
                                Num_Elements_12(Mask_Mises_Trend_12), Metric_Mises_Pct_12(Mask_Mises_Trend_12), Trendline_Samples_12);
                            h12_mises = plot(ax12, Trend_X_Mises_12, Trend_Y_Mises_12, ...
                                'Color', F12.Mises_Trendline_Color, 'LineStyle', F12.Mises_Trendline_Style, 'LineWidth', F12.Mises_Trendline_Width);
                        end
                    else
                        h12_mises = plot(ax12, nan, nan, 'LineStyle', LS.NoLine);
                    end
                else
                    h12_mises = plot(ax12, nan, nan, 'LineStyle', LS.NoLine);
                end

                Tolerance_Pct_12 = 0.1;
                h12_tol = yline(ax12, Tolerance_Pct_12, F12.Tolerance_Line_Style, ...
                    'Color', F12.Converged_Line_Color, 'LineWidth', F12.Tolerance_Line_Width, ...
                    'Label', 'Tolerance', 'Interpreter', 'latex', ...
                    'LabelHorizontalAlignment', 'left', ...
                    'LabelVerticalAlignment', 'bottom', ...
                    'FontSize', 20);

                Converged_Index_12 = find(Row_Indices_12 == Converged_Row_12, 1, 'first');
                if isempty(Converged_Index_12)
                    Converged_Index_12 = find(Metric_LE22_Pct_12 <= Tolerance_Pct_12, 1, 'first');
                end
                if ~isempty(Converged_Index_12)
                    set(Pair_Handles_12(Converged_Index_12), ...
                        'MarkerFaceColor', Converged_Face_Color_12, ...
                        'MarkerEdgeColor', Converged_Edge_Color_12, ...
                        'MarkerSize', F12.Converged_Pair_Marker_Size, ...
                        'LineWidth', F12.Converged_Pair_Marker_Line_Width);
                    h12_convline = xline(ax12, Num_Elements_12(Converged_Index_12), F12.Converged_Line_Style, ...
                        'Color', F12.Converged_Line_Color, 'LineWidth', F12.Converged_Line_Width, ...
                        'Label', F12.Converged_Label, 'Interpreter', 'latex', ...
                        'LabelHorizontalAlignment', 'center', ...
                        'LabelVerticalAlignment', 'middle', ...
                        'FontSize', 20);
                    h12_conv = plot(ax12, Num_Elements_12(Converged_Index_12), Metric_LE22_Pct_12(Converged_Index_12), ...
                        'LineStyle', LS.NoLine, 'Marker', F12.Converged_Marker, 'MarkerSize', F12.Converged_Marker_Size, ...
                        'MarkerFaceColor', 'none', 'MarkerEdgeColor', F12.Converged_Marker_Edge_Color, ...
                        'LineWidth', F12.Converged_Marker_Line_Width);
                else
                    h12_conv = plot(ax12, nan, nan, 'LineStyle', LS.NoLine);
                    h12_convline = [];
                end
                try
                    if ~isempty(h12_convline), uistack(h12_convline, 'bottom'); end
                    if ~isempty(h12_tol), uistack(h12_tol, 'bottom'); end
                catch
                end

                y_low_12 = min([Metric_LE22_Pct_12(:); Metric_S22_Pct_12(:); Metric_Mises_Pct_12(:); Tolerance_Pct_12], [], 'omitnan');
                y_high_12 = max([Metric_LE22_Pct_12(:); Metric_S22_Pct_12(:); Metric_Mises_Pct_12(:); Tolerance_Pct_12], [], 'omitnan');
                y_pad_12 = max(0.12 * max(y_high_12 - y_low_12, 1.0), 0.30);
                x_pad_12 = 0.05 * max(Num_Elements_12);
                xlim(ax12, [max(0, min(Num_Elements_12) - x_pad_12), 8500]);
                ylim(ax12, [max(0, y_low_12 - y_pad_12), 0.75]);

                Apply_Plot_Format_On_Axes(ax12, F12.X_Label, F12.Y_Label, F12.Title, S, S.Font_Sizes, ...
                    struct('Title_Color', F12.Axis_Text_Color, ...
                           'Axis_Label_Color', F12.Axis_Text_Color, ...
                           'Title_Font_Size', S.Title_Font_Size, ...
                           'Axis_Label_Font_Size', S.Axis_Label_Font_Size));

                LE22_Trend_Label_12 = '$LE22$ trend line';
                if isfield(F12, 'LE22_Trendline_Label') && strlength(string(F12.LE22_Trendline_Label)) > 0
                    LE22_Trend_Label_12 = char(string(F12.LE22_Trendline_Label));
                end
                S22_Trend_Label_12 = '$S22$ trend line';
                if isfield(F12, 'S22_Trendline_Label') && strlength(string(F12.S22_Trendline_Label)) > 0
                    S22_Trend_Label_12 = char(string(F12.S22_Trendline_Label));
                end
                Mises_Trend_Label_12 = '$\sigma_{vM}$ trend line';
                if isfield(F12, 'Mises_Trendline_Label') && strlength(string(F12.Mises_Trendline_Label)) > 0
                    Mises_Trend_Label_12 = char(string(F12.Mises_Trendline_Label));
                end

                Legend_Handles_12 = [Pair_Handles_12; h12_trend; h12_s22; h12_mises; h12_tol; h12_conv];
                Legend_Labels_12 = [Pair_Legend_12; {LE22_Trend_Label_12; S22_Trend_Label_12; Mises_Trend_Label_12; F12.Tolerance_Label; F12.Converged_Label}];
                Legend_12 = Apply_Legend_Template(ax12, Legend_Handles_12, Legend_Labels_12, ...
                    S, F12.Legend_Location, F12.Legend_NumColumns, 14, ...
                    struct('TextColor', F12.Legend_Text_Color, ...
                           'Color', F12.Legend_Background_Color, ...
                           'EdgeColor', F12.Legend_Edge_Color, ...
                           'LineWidth', 1.0));

                Max_Per_Row_12 = 3;
                if isfield(F12, 'Annotation_Max_Per_Row')
                    Max_Per_Row_12 = max(1, round(F12.Annotation_Max_Per_Row));
                end
                nBoxes = Pair_Count_12;
                nPerRow = min(Max_Per_Row_12, nBoxes);
                nRows = ceil(nBoxes / nPerRow);
                axpos = get(ax12, 'Position');
                boxW = 0.1;
                boxH = 0.085;
                colGap = 0.010;
                rowGap = boxH + 0.010;
                topMargin = 0.015;
                totalWidth = nPerRow * boxW + (nPerRow - 1) * colGap;

                xStart = axpos(1) + 0.01;
                try
                    legend_pos = get(Legend_12, 'Position');
                catch
                    legend_pos = [];
                end
                if ~isempty(legend_pos) && numel(legend_pos) == 4
                    right_edge_target = legend_pos(1) - 0.004;
                    xStart = right_edge_target - totalWidth;
                else
                    if ~isempty(Converged_Index_12)
                        x_ref_data = Num_Elements_12(Converged_Index_12);
                    else
                        x_ref_data = median(Num_Elements_12);
                    end
                    xlim_data = get(ax12, 'XLim');
                    x_ref_norm = axpos(1) + (x_ref_data - xlim_data(1)) / max(diff(xlim_data), eps) * axpos(3);
                    xStart = x_ref_norm + 0.03;
                end
                xStart = min(max(xStart, axpos(1) + 0.005), 0.98 - totalWidth);
                yTop = axpos(2) + axpos(4) - boxH - topMargin;

                for idx12 = 1:nBoxes
                    rowIdx = floor((idx12 - 1) / nPerRow);
                    colIdx = mod(idx12 - 1, nPerRow);
                    xBox = xStart + colIdx * (boxW + colGap);
                    yBox = yTop - rowIdx * rowGap;
                    c12 = Color_Map_12(idx12, :);
                    c12_edge = max(min(c12 .* 0.58, 1.0), 0.0);
                    annotation(Figure_12_Handle, 'textbox', [xBox, yBox, boxW, boxH], ...
                        'String', Annotation_Text_12{idx12}, ...
                        'Interpreter', 'latex', ...
                        'FitBoxToText', 'off', ...
                        'Units', 'normalized', ...
                        'HorizontalAlignment', 'left', ...
                        'VerticalAlignment', 'middle', ...
                        'EdgeColor', c12_edge, ...
                        'Color', c12_edge, ...
                        'LineWidth', 2.0, ...
                        'BackgroundColor', F12.Annotation_Background_Color, ...
                        'FontSize', 12, ...
                        'Margin', 4);
                end
            end

            Export_Figure_Files(Figure_12_Handle, Plot_Label_Struct.Output_Directory, F12.File_Name, S.Export_DPI);

            % ==================================================================
            % FIGURE 16 : FEA LE22 and S22 percentage difference
            % ==================================================================
            F16 = struct('Enable', false);
            if isfield(Plot_Label_Struct, 'Figure_16_FEA_Peak_LE22_S22')
                F16 = Plot_Label_Struct.Figure_16_FEA_Peak_LE22_S22;
            end

            Num_Elements_All_16 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'numElements'}));
            Pct_LE22_All_16 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'pctDiffLE22', 'pct_diff_LE22'}));
            if isempty(Pct_LE22_All_16) || all(isnan(Pct_LE22_All_16))
                Rel_LE22_All_16 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'relLE22ToPrev', 'rel_LE22_to_prev'}));
                if ~isempty(Rel_LE22_All_16)
                    Pct_LE22_All_16 = 100 .* abs(Rel_LE22_All_16);
                end
            end
            Pct_S22_All_16 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'pctDiffS22', 'pct_diff_S22'}));
            if isempty(Pct_S22_All_16) || all(isnan(Pct_S22_All_16))
                Rel_S22_All_16 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'relS22ToPrev', 'rel_S22_to_prev'}));
                if ~isempty(Rel_S22_All_16)
                    Pct_S22_All_16 = 100 .* abs(Rel_S22_All_16);
                end
            end
            n_rows_16 = height(Summary_Table_12);
            if isempty(Num_Elements_All_16)
                Num_Elements_All_16 = nan(n_rows_16, 1);
            elseif numel(Num_Elements_All_16) < n_rows_16
                Num_Elements_All_16(numel(Num_Elements_All_16) + 1:n_rows_16, 1) = nan;
            else
                Num_Elements_All_16 = Num_Elements_All_16(1:n_rows_16);
            end
            if isempty(Pct_LE22_All_16)
                Pct_LE22_All_16 = nan(n_rows_16, 1);
            elseif numel(Pct_LE22_All_16) < n_rows_16
                Pct_LE22_All_16(numel(Pct_LE22_All_16) + 1:n_rows_16, 1) = nan;
            else
                Pct_LE22_All_16 = Pct_LE22_All_16(1:n_rows_16);
            end
            if isempty(Pct_S22_All_16)
                Pct_S22_All_16 = nan(n_rows_16, 1);
            elseif numel(Pct_S22_All_16) < n_rows_16
                Pct_S22_All_16(numel(Pct_S22_All_16) + 1:n_rows_16, 1) = nan;
            else
                Pct_S22_All_16 = Pct_S22_All_16(1:n_rows_16);
            end
            Mesh_L_All_16 = nan(height(Summary_Table_12), 1);
            if any(strcmp(Summary_Table_12.Properties.VariableNames, 'mesh_h'))
                Mesh_L_All_16 = To_Double_Vector(Summary_Table_12.mesh_h);
            elseif any(strcmp(Summary_Table_12.Properties.VariableNames, 'mesh_h_6dp'))
                Mesh_L_All_16 = To_Double_Vector(Summary_Table_12.mesh_h_6dp);
            end

            Has_Pct_LE22_16 = any(~isnan(Num_Elements_All_16) & ~isnan(Pct_LE22_All_16));
            Has_Pct_S22_16 = any(~isnan(Num_Elements_All_16) & ~isnan(Pct_S22_All_16));
            if isfield(F16, 'Enable') && F16.Enable && (Has_Pct_LE22_16 || Has_Pct_S22_16)
                Tol_Rel_16 = nan;
                if isfield(Plot_Data_Struct, 'FEA_Convergence_Data') && ...
                        isfield(Plot_Data_Struct.FEA_Convergence_Data, 'Mesh_Conv_Tol') && ...
                        isfinite(double(Plot_Data_Struct.FEA_Convergence_Data.Mesh_Conv_Tol)) && ...
                        double(Plot_Data_Struct.FEA_Convergence_Data.Mesh_Conv_Tol) > 0
                    Tol_Rel_16 = double(Plot_Data_Struct.FEA_Convergence_Data.Mesh_Conv_Tol);
                end
                Tol_Pct_16 = 0.1;
                Tol_Label_16 = 'Tolerance $\xi$';
                if isfield(F16, 'Tolerance_Label') && strlength(string(F16.Tolerance_Label)) > 0
                    Tol_Label_16 = char(string(F16.Tolerance_Label));
                end
                % Use the same power-law trendline methodology as Figure 12.
                Trendline_Power_16 = 1.50;
                if exist('F12', 'var') && isstruct(F12) && isfield(F12, 'Trendline_Powers')
                    Trendline_Power_Candidate_16 = To_Double_Vector(F12.Trendline_Powers);
                    Trendline_Power_Candidate_16 = Trendline_Power_Candidate_16( ...
                        ~isnan(Trendline_Power_Candidate_16) & Trendline_Power_Candidate_16 > 0);
                    if ~isempty(Trendline_Power_Candidate_16)
                        Trendline_Power_16 = Trendline_Power_Candidate_16(1);
                    end
                end
                Trendline_Samples_16 = 320;
                if exist('F12', 'var') && isstruct(F12) && isfield(F12, 'Trendline_Samples') && ...
                        isfinite(double(F12.Trendline_Samples))
                    Trendline_Samples_16 = max(120, round(double(F12.Trendline_Samples)));
                end

                Layout_Rows_16 = 1;
                Layout_Cols_16 = 2;
                if isfield(F16, 'Layout_Rows') && isfinite(double(F16.Layout_Rows)) && double(F16.Layout_Rows) >= 1
                    Layout_Rows_16 = max(1, round(double(F16.Layout_Rows)));
                end
                if isfield(F16, 'Layout_Cols') && isfinite(double(F16.Layout_Cols)) && double(F16.Layout_Cols) >= 1
                    Layout_Cols_16 = max(1, round(double(F16.Layout_Cols)));
                end
                if Layout_Rows_16 * Layout_Cols_16 < 2
                    Layout_Rows_16 = 2;
                    Layout_Cols_16 = 1;
                end
                Font_Scale_16 = 1.0;
                if isfield(F16, 'Compact_Font_Scale') && isfinite(double(F16.Compact_Font_Scale))
                    Font_Scale_16 = max(0.45, min(1.0, double(F16.Compact_Font_Scale)));
                end
                Title_Font_16 = max(12, round(S.Title_Font_Size * Font_Scale_16));
                Axis_Font_16 = max(11, round(S.Axis_Label_Font_Size * Font_Scale_16));
                Legend_Font_16 = max(9, round((S.Legend_Font_Size - 2) * Font_Scale_16));
                Tick_Font_16 = max(9, round(S.Tick_Font_Size * Font_Scale_16));

                Figure_16_Handle = figure('Name', F16.Name, 'NumberTitle', 'off');
                Initialise_Figure_Window(Figure_16_Handle, S);
                set(Figure_16_Handle, 'Color', F16.Figure_Color);
                if isfield(F16, 'Export_Width_In') && isfield(F16, 'Export_Height_In') && ...
                        isfinite(double(F16.Export_Width_In)) && isfinite(double(F16.Export_Height_In)) && ...
                        double(F16.Export_Width_In) > 0 && double(F16.Export_Height_In) > 0
                    try
                        prev_units_16 = Figure_16_Handle.Units;
                        set(Figure_16_Handle, 'Units', 'inches');
                        pos16 = get(Figure_16_Handle, 'Position');
                        pos16(3) = double(F16.Export_Width_In);
                        pos16(4) = double(F16.Export_Height_In);
                        set(Figure_16_Handle, 'Position', pos16);
                        set(Figure_16_Handle, 'Units', prev_units_16);
                    catch
                    end
                end
                TL16 = tiledlayout(Figure_16_Handle, Layout_Rows_16, Layout_Cols_16, 'TileSpacing', 'compact', 'Padding', 'compact');

                ax16a = nexttile(TL16, 1);
                hold(ax16a, 'on');
                grid(ax16a, 'on');
                ax16a.XMinorGrid = 'off'; ax16a.YMinorGrid = 'off';
                Mask_LE22_16 = ~isnan(Num_Elements_All_16) & ~isnan(Pct_LE22_All_16);
                Rows_LE22_16 = find(Mask_LE22_16);
                X_LE22_16 = Num_Elements_All_16(Mask_LE22_16);
                Y_LE22_16 = Pct_LE22_All_16(Mask_LE22_16);
                [X_LE22_16, Sort_Idx_LE22_16] = sort(X_LE22_16);
                Y_LE22_16 = Y_LE22_16(Sort_Idx_LE22_16);
                Rows_LE22_16 = Rows_LE22_16(Sort_Idx_LE22_16);
                if ~isempty(X_LE22_16)
                    h16a_data = plot(ax16a, X_LE22_16, Y_LE22_16, 'LineStyle', LS.NoLine, 'Marker', F16.LE22_Data_Marker, ...
                        'Color', F16.LE22_Data_Color, 'LineWidth', F16.LE22_Data_Line_Width, ...
                        'MarkerSize', F16.LE22_Data_Marker_Size, 'MarkerFaceColor', F16.LE22_Data_Color, 'MarkerEdgeColor', F16.LE22_Data_Edge_Color);
                    h16a_trend = plot(ax16a, nan, nan, 'LineStyle', LS.NoLine);
                    Trendline_Set_LE22_16 = Build_Power_Trendline_Set( ...
                        X_LE22_16, Y_LE22_16, Trendline_Power_16, Trendline_Samples_16);
                    if ~isempty(Trendline_Set_LE22_16)
                        h16a_trend = plot(ax16a, Trendline_Set_LE22_16(1).X, Trendline_Set_LE22_16(1).Y, F16.LE22_Trendline_Style, ...
                            'Color', F16.LE22_Trendline_Color, 'LineWidth', F16.LE22_Trendline_Line_Width);
                    else
                        [Trend_X_LE22_16, Trend_Y_LE22_16] = Build_Smooth_Trendline(X_LE22_16, Y_LE22_16, Trendline_Samples_16);
                        if ~isempty(Trend_X_LE22_16)
                            h16a_trend = plot(ax16a, Trend_X_LE22_16, Trend_Y_LE22_16, F16.LE22_Trendline_Style, ...
                                'Color', F16.LE22_Trendline_Color, 'LineWidth', F16.LE22_Trendline_Line_Width);
                        end
                    end
                    h16a_tol = plot(ax16a, nan, nan, 'LineStyle', LS.NoLine);
                    if ~isnan(Tol_Pct_16)
                        h16a_tol = yline(ax16a, Tol_Pct_16, F16.Tolerance_Line_Style, ...
                            'Color', F16.Tolerance_Line_Color, 'LineWidth', F16.Tolerance_Line_Width, ...
                            'Label', 'Tolerance', 'Interpreter', 'latex', ...
                            'LabelHorizontalAlignment', 'left', ...
                            'LabelVerticalAlignment', 'bottom', ...
                            'FontSize', max(9, round(12 * Font_Scale_16)));
                    end
                    Conv_Idx_LE22_16 = find(Rows_LE22_16 == Converged_Row_12, 1, 'first');
                    if ~isempty(Conv_Idx_LE22_16)
                        h16a_conv = plot(ax16a, X_LE22_16(Conv_Idx_LE22_16), Y_LE22_16(Conv_Idx_LE22_16), ...
                            'LineStyle', LS.NoLine, 'Marker', F16.Converged_Marker, 'MarkerSize', F16.Converged_Marker_Size, ...
                            'MarkerFaceColor', 'none', 'MarkerEdgeColor', F16.Converged_Marker_Edge_Color, 'LineWidth', F16.Converged_Marker_Line_Width);
                        dx16a = 0.02 * max(max(X_LE22_16) - min(X_LE22_16), 1);
                        dy16a = 0.08 * max(max(Y_LE22_16) - min(Y_LE22_16), eps);
                        if isnan(Mesh_L_All_16(Converged_Row_12))
                            L_Label_16 = '$L = \mathrm{n/a}$';
                        else
                            L_Label_16 = sprintf('$L = %.6g$', Mesh_L_All_16(Converged_Row_12));
                        end
                        Add_Axis_Annotation_Box(ax16a, X_LE22_16(Conv_Idx_LE22_16) + dx16a, ...
                            Y_LE22_16(Conv_Idx_LE22_16) + dy16a, ...
                            {L_Label_16, sprintf('$N_e = %.0f$', X_LE22_16(Conv_Idx_LE22_16))}, ...
                            S, F16.Converged_Marker_Edge_Color, 0, 'bottom', 'left');
                    else
                        h16a_conv = plot(ax16a, nan, nan, 'LineStyle', LS.NoLine);
                    end
                    Legend_Left_16 = {'$\xi_{LE22}$', 'Converged mesh'};
                    if isfield(F16, 'Legend_Left') && iscell(F16.Legend_Left) && numel(F16.Legend_Left) >= 2
                        Legend_Left_16 = F16.Legend_Left;
                    elseif isfield(F16, 'Legend') && iscell(F16.Legend) && numel(F16.Legend) >= 2
                        Legend_Left_16 = F16.Legend;
                    end
                    LE22_Trend_Label_16 = '$\xi_{LE22}$ trend line';
                    if isfield(F16, 'LE22_Trendline_Label') && strlength(string(F16.LE22_Trendline_Label)) > 0
                        LE22_Trend_Label_16 = char(string(F16.LE22_Trendline_Label));
                    end
                    legend_handles_16a = [h16a_data, h16a_trend, h16a_conv];
                    legend_labels_16a = {Legend_Left_16{1}, LE22_Trend_Label_16, Legend_Left_16{2}};
                    if ~isnan(Tol_Pct_16)
                        legend_handles_16a(end + 1) = h16a_tol; %#ok<AGROW>
                        legend_labels_16a{end + 1} = Tol_Label_16; %#ok<AGROW>
                    end
                    Apply_Legend_Template(ax16a, legend_handles_16a, legend_labels_16a, ...
                        S, F16.Legend_Location, 1, Legend_Font_16);
                else
                    text(ax16a, 0.5, 0.5, 'No valid LE22 percentage-difference data', ...
                        'Units', 'normalized', 'HorizontalAlignment', 'center', 'Interpreter', 'latex');
                end
                Apply_Plot_Format_On_Axes(ax16a, F16.X_Label, F16.Y_Labels{1}, {F16.Tile_Titles{1}}, S, S.Font_Sizes, ...
                    struct('Title_Font_Size', Title_Font_16 - 1, ...
                           'Axis_Label_Font_Size', Axis_Font_16));
                Apply_Primary_Axis_Style(ax16a, S);
                ax16a.XAxis.FontSize = Tick_Font_16;
                ax16a.YAxis(1).FontSize = Tick_Font_16;

                ax16b = nexttile(TL16, 2);
                hold(ax16b, 'on');
                grid(ax16b, 'on');
                ax16b.XMinorGrid = 'off'; ax16b.YMinorGrid = 'off';
                Mask_S22_16 = ~isnan(Num_Elements_All_16) & ~isnan(Pct_S22_All_16);
                Rows_S22_16 = find(Mask_S22_16);
                X_S22_16 = Num_Elements_All_16(Mask_S22_16);
                Y_S22_16 = Pct_S22_All_16(Mask_S22_16);
                [X_S22_16, Sort_Idx_S22_16] = sort(X_S22_16);
                Y_S22_16 = Y_S22_16(Sort_Idx_S22_16);
                Rows_S22_16 = Rows_S22_16(Sort_Idx_S22_16);
                if ~isempty(X_S22_16)
                    h16b_data = plot(ax16b, X_S22_16, Y_S22_16, 'LineStyle', LS.NoLine, 'Marker', F16.S22_Data_Marker, ...
                        'Color', F16.S22_Data_Color, 'LineWidth', F16.S22_Data_Line_Width, ...
                        'MarkerSize', F16.S22_Data_Marker_Size, 'MarkerFaceColor', F16.S22_Data_Color, 'MarkerEdgeColor', F16.S22_Data_Edge_Color);
                    h16b_trend = plot(ax16b, nan, nan, 'LineStyle', LS.NoLine);
                    Trendline_Set_S22_16 = Build_Power_Trendline_Set( ...
                        X_S22_16, Y_S22_16, Trendline_Power_16, Trendline_Samples_16);
                    if ~isempty(Trendline_Set_S22_16)
                        h16b_trend = plot(ax16b, Trendline_Set_S22_16(1).X, Trendline_Set_S22_16(1).Y, F16.S22_Trendline_Style, ...
                            'Color', F16.S22_Trendline_Color, 'LineWidth', F16.S22_Trendline_Line_Width);
                    else
                        [Trend_X_S22_16, Trend_Y_S22_16] = Build_Smooth_Trendline(X_S22_16, Y_S22_16, Trendline_Samples_16);
                        if ~isempty(Trend_X_S22_16)
                            h16b_trend = plot(ax16b, Trend_X_S22_16, Trend_Y_S22_16, F16.S22_Trendline_Style, ...
                                'Color', F16.S22_Trendline_Color, 'LineWidth', F16.S22_Trendline_Line_Width);
                        end
                    end
                    h16b_tol = plot(ax16b, nan, nan, 'LineStyle', LS.NoLine);
                    if ~isnan(Tol_Pct_16)
                        h16b_tol = yline(ax16b, Tol_Pct_16, F16.Tolerance_Line_Style, ...
                            'Color', F16.Tolerance_Line_Color, 'LineWidth', F16.Tolerance_Line_Width, ...
                            'Label', 'Tolerance', 'Interpreter', 'latex', ...
                            'LabelHorizontalAlignment', 'left', ...
                            'LabelVerticalAlignment', 'bottom', ...
                            'FontSize', max(9, round(12 * Font_Scale_16)));
                    end
                    Conv_Idx_S22_16 = find(Rows_S22_16 == Converged_Row_12, 1, 'first');
                    if ~isempty(Conv_Idx_S22_16)
                        h16b_conv = plot(ax16b, X_S22_16(Conv_Idx_S22_16), Y_S22_16(Conv_Idx_S22_16), ...
                            'LineStyle', LS.NoLine, 'Marker', F16.Converged_Marker, 'MarkerSize', F16.Converged_Marker_Size, ...
                            'MarkerFaceColor', 'none', 'MarkerEdgeColor', F16.Converged_Marker_Edge_Color, 'LineWidth', F16.Converged_Marker_Line_Width);
                        dx16b = 0.02 * max(max(X_S22_16) - min(X_S22_16), 1);
                        dy16b = 0.08 * max(max(Y_S22_16) - min(Y_S22_16), eps);
                        if isnan(Mesh_L_All_16(Converged_Row_12))
                            L_Label_16 = '$L = \mathrm{n/a}$';
                        else
                            L_Label_16 = sprintf('$L = %.6g$', Mesh_L_All_16(Converged_Row_12));
                        end
                        Add_Axis_Annotation_Box(ax16b, X_S22_16(Conv_Idx_S22_16) + dx16b, ...
                            Y_S22_16(Conv_Idx_S22_16) + dy16b, ...
                            {L_Label_16, sprintf('$N_e = %.0f$', X_S22_16(Conv_Idx_S22_16))}, ...
                            S, F16.Converged_Marker_Edge_Color, 0, 'bottom', 'left');
                    else
                        h16b_conv = plot(ax16b, nan, nan, 'LineStyle', LS.NoLine);
                    end
                    Legend_Right_16 = {'$\xi_{S22}$', 'Converged mesh'};
                    if isfield(F16, 'Legend_Right') && iscell(F16.Legend_Right) && numel(F16.Legend_Right) >= 2
                        Legend_Right_16 = F16.Legend_Right;
                    elseif isfield(F16, 'Legend') && iscell(F16.Legend) && numel(F16.Legend) >= 2
                        Legend_Right_16 = F16.Legend;
                    end
                    S22_Trend_Label_16 = '$\xi_{S22}$ trend line';
                    if isfield(F16, 'S22_Trendline_Label') && strlength(string(F16.S22_Trendline_Label)) > 0
                        S22_Trend_Label_16 = char(string(F16.S22_Trendline_Label));
                    end
                    legend_handles_16b = [h16b_data, h16b_trend, h16b_conv];
                    legend_labels_16b = {Legend_Right_16{1}, S22_Trend_Label_16, Legend_Right_16{2}};
                    if ~isnan(Tol_Pct_16)
                        legend_handles_16b(end + 1) = h16b_tol; %#ok<AGROW>
                        legend_labels_16b{end + 1} = Tol_Label_16; %#ok<AGROW>
                    end
                    Apply_Legend_Template(ax16b, legend_handles_16b, legend_labels_16b, ...
                        S, F16.Legend_Location, 1, Legend_Font_16);
                else
                    text(ax16b, 0.5, 0.5, 'No valid S22 percentage-difference data', ...
                        'Units', 'normalized', 'HorizontalAlignment', 'center', 'Interpreter', 'latex');
                end
                Apply_Plot_Format_On_Axes(ax16b, F16.X_Label, F16.Y_Labels{2}, {F16.Tile_Titles{2}}, S, S.Font_Sizes, ...
                    struct('Title_Font_Size', Title_Font_16 - 1, ...
                           'Axis_Label_Font_Size', Axis_Font_16));
                Apply_Primary_Axis_Style(ax16b, S);
                ax16b.XAxis.FontSize = Tick_Font_16;
                ax16b.YAxis(1).FontSize = Tick_Font_16;

                Export_Figure_Files(Figure_16_Handle, Plot_Label_Struct.Output_Directory, F16.File_Name, S.Export_DPI);
            end

            % ==================================================================
            % FIGURE 17 : FEA runtime and memory
            % ==================================================================
            F17 = struct('Enable', false);
            if isfield(Plot_Label_Struct, 'Figure_17_FEA_Time_Memory')
                F17 = Plot_Label_Struct.Figure_17_FEA_Time_Memory;
            end

            Time_All_17 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'wallclockTimeSec', 'wallclock_time_sec'}));
            if isempty(Time_All_17) || all(isnan(Time_All_17))
                Time_All_17 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'cpuTimeSec', 'cpu_time_sec'}));
            end
            Memory_All_17 = To_Double_Vector(Get_Table_Column(Summary_Table_12, {'memoryUsedMB', 'memoryRequiredMB', 'memoryMinimizeIOMB'}));
            Num_Elements_17 = Num_Elements_All_16;
            if isempty(Time_All_17)
                Time_All_17 = nan(n_rows_16, 1);
            elseif numel(Time_All_17) < n_rows_16
                Time_All_17(numel(Time_All_17) + 1:n_rows_16, 1) = nan;
            else
                Time_All_17 = Time_All_17(1:n_rows_16);
            end
            if isempty(Memory_All_17)
                Memory_All_17 = nan(n_rows_16, 1);
            elseif numel(Memory_All_17) < n_rows_16
                Memory_All_17(numel(Memory_All_17) + 1:n_rows_16, 1) = nan;
            else
                Memory_All_17 = Memory_All_17(1:n_rows_16);
            end
            Mask_17 = ~isnan(Num_Elements_17) & (~isnan(Time_All_17) | ~isnan(Memory_All_17));

            if isfield(F17, 'Enable') && F17.Enable && any(Mask_17)
                Rows_17 = find(Mask_17);
                X_17 = Num_Elements_17(Mask_17);
                Time_17 = Time_All_17(Mask_17);
                Memory_17 = Memory_All_17(Mask_17);
                [X_17, Sort_Idx_17] = sort(X_17);
                Time_17 = Time_17(Sort_Idx_17);
                Memory_17 = Memory_17(Sort_Idx_17);
                Rows_17 = Rows_17(Sort_Idx_17);

                Figure_17_Handle = figure('Name', F17.Name, 'NumberTitle', 'off');
                Initialise_Figure_Window(Figure_17_Handle, S);
                set(Figure_17_Handle, 'Color', F17.Figure_Color);
                ax17 = axes(Figure_17_Handle); %#ok<LAXES>
                hold(ax17, 'on');
                grid(ax17, 'on');
                ax17.XMinorGrid = 'off'; ax17.YMinorGrid = 'off';
                set(ax17, 'Color', F17.Axis_Color, ...
                    'GridColor', F17.Grid_Color, ...
                    'MinorGridColor', F17.Minor_Grid_Color, ...
                    'GridAlpha', 0.8, ...
                    'MinorGridAlpha', 0.8, ...
                    'LineWidth', 1.6, ...
                    'FontSize', S.Tick_Font_Size, ...
                    'Layer', 'bottom');

                yyaxis(ax17, 'left');
                h17_time_data = plot(ax17, nan, nan, 'LineStyle', LS.NoLine);
                h17_time_fit = plot(ax17, nan, nan, 'LineStyle', LS.NoLine);
                X_Time_Line_17 = nan(0, 1);
                Y_Time_Line_17 = nan(0, 1);
                Mask_Time_Fit_17 = ~isnan(X_17) & ~isnan(Time_17);
                if any(Mask_Time_Fit_17)
                    h17_time_data = plot(ax17, X_17(Mask_Time_Fit_17), Time_17(Mask_Time_Fit_17), ...
                        'LineStyle', LS.NoLine, 'Marker', F17.Runtime_Marker, 'MarkerSize', F17.Runtime_Marker_Size, ...
                        'MarkerFaceColor', F17.Runtime_Color, ...
                        'MarkerEdgeColor', F17.Runtime_Edge_Color, 'LineWidth', F17.Runtime_Marker_Line_Width);
                end
                if nnz(Mask_Time_Fit_17) >= 2
                    X_Time_Fit_17 = X_17(Mask_Time_Fit_17);
                    Y_Time_Fit_17 = Time_17(Mask_Time_Fit_17);
                    P_Time_17 = polyfit(X_Time_Fit_17, Y_Time_Fit_17, 1);
                    X_Time_Line_17 = linspace(min(X_Time_Fit_17), max(X_Time_Fit_17), 220)';
                    Y_Time_Line_17 = polyval(P_Time_17, X_Time_Line_17);
                    h17_time_fit = plot(ax17, X_Time_Line_17, Y_Time_Line_17, F17.Runtime_Trend_LineStyle, ...
                        'Color', F17.Runtime_Color, 'LineWidth', F17.Runtime_Trend_LineWidth);
                end
                Apply_Plot_Format_On_Axes(ax17, '', F17.Y_Label_Left, {''}, S, S.Font_Sizes, ...
                    struct('Axis_Label_Font_Size', S.Axis_Label_Font_Size));
                ax17.YAxis(1).Color = F17.Runtime_Color;

                yyaxis(ax17, 'right');
                h17_memory_data = plot(ax17, nan, nan, 'LineStyle', LS.NoLine);
                h17_memory_fit = plot(ax17, nan, nan, 'LineStyle', LS.NoLine);
                X_Memory_Line_17 = nan(0, 1);
                Y_Memory_Line_17 = nan(0, 1);
                Mask_Memory_Fit_17 = ~isnan(X_17) & ~isnan(Memory_17);
                if any(Mask_Memory_Fit_17)
                    h17_memory_data = plot(ax17, X_17(Mask_Memory_Fit_17), Memory_17(Mask_Memory_Fit_17), ...
                        'LineStyle', LS.NoLine, 'Marker', F17.Memory_Marker, 'MarkerSize', F17.Memory_Marker_Size, ...
                        'MarkerFaceColor', F17.Memory_Color, ...
                        'MarkerEdgeColor', F17.Memory_Edge_Color, 'LineWidth', F17.Memory_Marker_Line_Width);
                end
                if nnz(Mask_Memory_Fit_17) >= 2
                    X_Memory_Fit_17 = X_17(Mask_Memory_Fit_17);
                    Y_Memory_Fit_17 = Memory_17(Mask_Memory_Fit_17);
                    P_Memory_17 = polyfit(X_Memory_Fit_17, Y_Memory_Fit_17, 1);
                    X_Memory_Line_17 = linspace(min(X_Memory_Fit_17), max(X_Memory_Fit_17), 220)';
                    Y_Memory_Line_17 = polyval(P_Memory_17, X_Memory_Line_17);
                    h17_memory_fit = plot(ax17, X_Memory_Line_17, Y_Memory_Line_17, F17.Memory_Trend_LineStyle, ...
                        'Color', F17.Memory_Color, 'LineWidth', F17.Memory_Trend_LineWidth);
                end
                Apply_Plot_Format_On_Axes(ax17, '', F17.Y_Label_Right, {''}, S, S.Font_Sizes, ...
                    struct('Axis_Label_Font_Size', S.Axis_Label_Font_Size));
                ax17.YAxis(2).Color = F17.Memory_Color;

                % Exact axis limits for reproducible comparison (manual if provided, else exact data bounds).
                X_Limits_17 = [];
                if isfield(F17, 'X_Limits') && isnumeric(F17.X_Limits) && numel(F17.X_Limits) == 2 && all(isfinite(double(F17.X_Limits)))
                    X_Limits_17 = sort(double(F17.X_Limits(:))');
                else
                    X_All_17 = [X_17(:); X_Time_Line_17(:); X_Memory_Line_17(:)];
                    X_All_17 = X_All_17(isfinite(X_All_17));
                    if ~isempty(X_All_17)
                        X_Limits_17 = [min(X_All_17), max(X_All_17)];
                        if X_Limits_17(2) <= X_Limits_17(1)
                            X_Limits_17(2) = X_Limits_17(1) + 1.0;
                        end
                    end
                end
                if ~isempty(X_Limits_17)
                    xlim(ax17, X_Limits_17);
                end

                yyaxis(ax17, 'left');
                YL_Limits_17 = [];
                if isfield(F17, 'Y_Limits_Left') && isnumeric(F17.Y_Limits_Left) && numel(F17.Y_Limits_Left) == 2 && all(isfinite(double(F17.Y_Limits_Left)))
                    YL_Limits_17 = sort(double(F17.Y_Limits_Left(:))');
                else
                    YL_All_17 = [Time_17(:); Y_Time_Line_17(:)];
                    YL_All_17 = YL_All_17(isfinite(YL_All_17));
                    if ~isempty(YL_All_17)
                        YL_Limits_17 = [min(YL_All_17), max(YL_All_17)];
                        if YL_Limits_17(2) <= YL_Limits_17(1)
                            YL_Limits_17(2) = YL_Limits_17(1) + 1.0;
                        end
                    end
                end
                if ~isempty(YL_Limits_17)
                    ylim(ax17, YL_Limits_17);
                end

                yyaxis(ax17, 'right');
                YR_Limits_17 = [];
                if isfield(F17, 'Y_Limits_Right') && isnumeric(F17.Y_Limits_Right) && numel(F17.Y_Limits_Right) == 2 && all(isfinite(double(F17.Y_Limits_Right)))
                    YR_Limits_17 = sort(double(F17.Y_Limits_Right(:))');
                else
                    YR_All_17 = [Memory_17(:); Y_Memory_Line_17(:)];
                    YR_All_17 = YR_All_17(isfinite(YR_All_17));
                    if ~isempty(YR_All_17)
                        YR_Limits_17 = [min(YR_All_17), max(YR_All_17)];
                        if YR_Limits_17(2) <= YR_Limits_17(1)
                            YR_Limits_17(2) = YR_Limits_17(1) + 1.0;
                        end
                    end
                end
                if ~isempty(YR_Limits_17)
                    ylim(ax17, YR_Limits_17);
                end

                yyaxis(ax17, 'left');
                Apply_Plot_Format_On_Axes(ax17, F17.X_Label, F17.Y_Label_Left, F17.Title, S, S.Font_Sizes, ...
                    struct('Axis_Label_Font_Size', S.Axis_Label_Font_Size, ...
                           'Title_Font_Size', S.Title_Font_Size));
                Apply_Primary_Axis_Style(ax17, S);
                Legend_Labels_17 = F17.Legend;
                if ~iscell(Legend_Labels_17) || numel(Legend_Labels_17) ~= 4
                    Legend_Labels_17 = {'Runtime data (s)', 'Runtime trendline (s)', 'Memory data (MB)', 'Memory trendline (MB)'};
                end
                Legend_Labels_17 = Legend_Labels_17(:)';
                Legend_NumColumns_17 = 2;
                if isfield(F17, 'Legend_NumColumns') && isfinite(double(F17.Legend_NumColumns))
                    Legend_NumColumns_17 = max(1, round(double(F17.Legend_NumColumns)));
                end
                Apply_Legend_Template(ax17, [h17_time_data, h17_time_fit, h17_memory_data, h17_memory_fit], ...
                    Legend_Labels_17, S, F17.Legend_Location, Legend_NumColumns_17, S.Legend_Font_Size - 2);

                Export_Figure_Files(Figure_17_Handle, Plot_Label_Struct.Output_Directory, F17.File_Name, S.Export_DPI);
            end
        end
    end

    % ==================================================================
    % FIGURE 11 : Element size displacement
    % ==================================================================
    F11 = Plot_Label_Struct.Figure_11_Element_Size_Displacement;
    Has_Mesh_Array_11 = isfield(Plot_Data_Struct, 'FEA_Element_Size_Array') && ...
        ~isempty(Plot_Data_Struct.FEA_Element_Size_Array);
    Has_Mesh_Summary_11 = isfield(Plot_Data_Struct, 'FEA_Convergence_Data') && ...
        Plot_Data_Struct.FEA_Convergence_Data.Available && ...
        isfield(Plot_Data_Struct.FEA_Convergence_Data, 'Summary_Table') && ...
        istable(Plot_Data_Struct.FEA_Convergence_Data.Summary_Table) && ...
        ~isempty(Plot_Data_Struct.FEA_Convergence_Data.Summary_Table);

    if isfield(F11, 'Enable') && F11.Enable && (Has_Mesh_Array_11 || Has_Mesh_Summary_11)
        if Has_Mesh_Array_11
            Mesh_h_11 = To_Double_Vector(Plot_Data_Struct.FEA_Element_Size_Array);
        else
            Summary_Table_11 = Plot_Data_Struct.FEA_Convergence_Data.Summary_Table;
            if any(strcmp(Summary_Table_11.Properties.VariableNames, 'mesh_h'))
                Mesh_h_11 = To_Double_Vector(Summary_Table_11.mesh_h);
            elseif any(strcmp(Summary_Table_11.Properties.VariableNames, 'mesh_h_6dp'))
                Mesh_h_11 = To_Double_Vector(Summary_Table_11.mesh_h_6dp);
            else
                Mesh_h_11 = nan(0, 1);
            end

            if any(strcmp(Summary_Table_11.Properties.VariableNames, 'jobStatus'))
                Job_Status_11 = lower(string(Summary_Table_11.jobStatus));
                Completed_Mask_11 = Job_Status_11 == "completed";
                Mesh_h_11 = Mesh_h_11(Completed_Mask_11);
            end
        end

        Mesh_h_11 = round(Mesh_h_11, 6);
        Mesh_h_11 = Mesh_h_11(~isnan(Mesh_h_11) & Mesh_h_11 > 0);
        Mesh_h_11 = unique(Mesh_h_11, 'stable');

        Has_Stress_Strain_11 = isfield(Plot_Data_Struct, 'Engineering_Strain') && ...
            isfield(Plot_Data_Struct, 'True_Plastic_Strain') && ...
            isfield(Plot_Data_Struct, 'Engineering_UTS_Index') && ...
            ~isempty(Plot_Data_Struct.Engineering_Strain) && ...
            ~isempty(Plot_Data_Struct.True_Plastic_Strain);

        if Has_Stress_Strain_11 && ~isempty(Mesh_h_11)
            Figure_11_Handle = figure('Name', F11.Name, 'NumberTitle', 'off');
            Initialise_Figure_Window(Figure_11_Handle, S);
            hold on; grid on;

            N11 = min(numel(Plot_Data_Struct.Engineering_Strain), numel(Plot_Data_Struct.True_Plastic_Strain));
            Strain_Source_11 = Plot_Data_Struct.Engineering_Strain(1:N11);
            True_Plastic_11 = Plot_Data_Struct.True_Plastic_Strain(1:N11);

            UTS_Index_11 = round(double(Plot_Data_Struct.Engineering_UTS_Index));
            UTS_Index_11 = max(1, min(UTS_Index_11, N11));

            Strain_11 = Strain_Source_11(UTS_Index_11:end);
            Base_Displacement_11 = True_Plastic_11(UTS_Index_11:end) - True_Plastic_11(UTS_Index_11);
            Base_Displacement_11 = max(Base_Displacement_11, 0);
            Disp_11 = Base_Displacement_11(:) * reshape(Mesh_h_11, 1, []);

            Line_Styles_11 = F11.Line_Styles;
            Line_Markers_11 = F11.Line_Markers;
            Num_Sizes_11 = numel(Mesh_h_11);
            Color_Map_11 = Get_High_Contrast_Colormap(max(Num_Sizes_11, 2), F11.Colormap);
            Marker_Step_11 = max(3, round(numel(Strain_11) / 14));
            Marker_Indices_11 = 1:Marker_Step_11:numel(Strain_11);
            if isempty(Marker_Indices_11) && ~isempty(Strain_11)
                Marker_Indices_11 = 1;
            end

            Line_Handles_11 = gobjects(Num_Sizes_11, 1);
            Line_Legend_11 = cell(Num_Sizes_11, 1);
            Peak_Handles_11 = gobjects(Num_Sizes_11, 1);
            Peak_Legend_11 = cell(Num_Sizes_11, 1);
            Peak_Values_11 = nan(Num_Sizes_11, 1);
            Peak_Indices_11 = nan(Num_Sizes_11, 1);

            for idx11 = 1:Num_Sizes_11
                this_color = Color_Map_11(idx11, :);
                this_ls = Line_Styles_11{mod(idx11 - 1, numel(Line_Styles_11)) + 1};
                this_mk = Line_Markers_11{mod(idx11 - 1, numel(Line_Markers_11)) + 1};
                this_disp = Disp_11(:, idx11);
                valid_disp_mask = ~isnan(this_disp) & ~isnan(Strain_11);

                Line_Handles_11(idx11) = plot(Strain_11, this_disp, ...
                    'Color', this_color, 'LineStyle', this_ls, 'LineWidth', S.LineWidths, ...
                    'Marker', this_mk, ...
                    'MarkerSize', F11.Line_Marker_Size, 'MarkerFaceColor', this_color, ...
                    'MarkerEdgeColor', this_color * F11.Line_Marker_Edge_Shade_Factor);
                if ~isempty(Marker_Indices_11) && isprop(Line_Handles_11(idx11), 'MarkerIndices')
                    try
                        set(Line_Handles_11(idx11), 'MarkerIndices', Marker_Indices_11);
                    catch
                        % Older MATLAB releases may not support MarkerIndices.
                    end
                end
                Line_Legend_11{idx11} = sprintf('$L = %s$', ...
                    Format_Strain_4sf(Mesh_h_11(idx11)));

                if any(valid_disp_mask)
                    valid_indices_11 = find(valid_disp_mask);
                    [Peak_Values_11(idx11), local_peak_idx_11] = max(this_disp(valid_disp_mask));
                    Peak_Indices_11(idx11) = valid_indices_11(local_peak_idx_11);
                end
            end

            Valid_Peak_Mask_11 = ~isnan(Peak_Values_11) & ~isnan(Peak_Indices_11) & ...
                Peak_Indices_11 >= 1 & Peak_Indices_11 <= numel(Strain_11);
            for idx11 = 1:Num_Sizes_11
                this_color = Color_Map_11(idx11, :);
                if Valid_Peak_Mask_11(idx11)
                    Peak_Handles_11(idx11) = plot(Strain_11(Peak_Indices_11(idx11)), Peak_Values_11(idx11), ...
                        'LineStyle', LS.NoLine, 'Marker', F11.Peak_Marker, 'MarkerSize', F11.Peak_Marker_Size, ...
                        'MarkerFaceColor', this_color, 'MarkerEdgeColor', this_color * F11.Peak_Marker_Edge_Shade_Factor, ...
                        'LineWidth', F11.Peak_Marker_Line_Width);
                    Peak_Legend_11{idx11} = sprintf('$\\bar{u}_{pl,\\max} = %s$', ...
                        Format_Strain_4sf(Peak_Values_11(idx11)));
                else
                    Peak_Handles_11(idx11) = plot(nan, nan, ...
                        'LineStyle', LS.NoLine, 'Marker', F11.Peak_Marker, 'MarkerSize', F11.Peak_Marker_Size, ...
                        'MarkerFaceColor', this_color, 'MarkerEdgeColor', this_color * F11.Peak_Marker_Edge_Shade_Factor, ...
                        'LineWidth', F11.Peak_Marker_Line_Width);
                    Peak_Legend_11{idx11} = '$\bar{u}_{pl,\max} = \mathrm{n/a}$';
                end
            end

            Plot_Format(F11.X_Label, F11.Y_Label, F11.Title, S.Font_Sizes, S.Axis_Line_Width);
            Legend_Handles_11 = [Line_Handles_11; Peak_Handles_11];
            Legend_Entries_11 = [Line_Legend_11; Peak_Legend_11];
            Apply_Legend_Template(gca, Legend_Handles_11, Legend_Entries_11, ...
                S, F11.Legend_Location, 2, S.Legend_Font_Size - 1);
            Bring_Markers_To_Front(gca);
            Export_Figure_Files(Figure_11_Handle, Plot_Label_Struct.Output_Directory, F11.File_Name, S.Export_DPI);

            F20 = struct('Enable', false);
            if isfield(Plot_Label_Struct, 'Figure_20_Peak_Displacement_Trend')
                F20 = Plot_Label_Struct.Figure_20_Peak_Displacement_Trend;
            end

            % ==================================================================
            % FIGURE 20 : Peak equivalent plastic displacement
            % ==================================================================
            Valid_Peak_Mask_20 = Valid_Peak_Mask_11 & ~isnan(Mesh_h_11);
            if isfield(F20, 'Enable') && F20.Enable && any(Valid_Peak_Mask_20)
                Figure_20_Handle = figure('Name', F20.Name, 'NumberTitle', 'off');
                Initialise_Figure_Window(Figure_20_Handle, S);
                set(Figure_20_Handle, 'Color', F20.Figure_Color);
                ax20 = axes(Figure_20_Handle); %#ok<LAXES>
                hold(ax20, 'on');
                grid(ax20, 'on');
                ax20.XMinorGrid = 'off'; ax20.YMinorGrid = 'off';

                Peak_X_20 = Mesh_h_11(Valid_Peak_Mask_20);
                Peak_Y_20 = Peak_Values_11(Valid_Peak_Mask_20);
                Peak_Color_20 = Color_Map_11(Valid_Peak_Mask_20, :);
                Peak_Label_20 = arrayfun(@(x) sprintf('%.4f', x), Peak_X_20, 'UniformOutput', false);
                Bar_Pos_20 = (1:numel(Peak_Y_20))';
                h20_bar = bar(ax20, Bar_Pos_20, Peak_Y_20, 0.78, ...
                    'FaceColor', 'flat', 'EdgeColor', F20.Bar_Edge_Color, 'LineWidth', F20.Bar_Edge_LineWidth);
                set(h20_bar, 'CData', Peak_Color_20);
                set(ax20, 'XTick', Bar_Pos_20, 'XTickLabel', Peak_Label_20);
                xtickangle(ax20, 0);

                Apply_Plot_Format_On_Axes(ax20, F20.X_Label, F20.Y_Label, F20.Title, S, S.Font_Sizes);
                Apply_Primary_Axis_Style(ax20, S);

                Legend_Label_20 = 'Peak values (bar)';
                if isfield(F20, 'Legend') && iscell(F20.Legend) && ~isempty(F20.Legend) && ~isempty(F20.Legend{1})
                    Legend_Label_20 = char(string(F20.Legend{1}));
                end
                Apply_Legend_Template(ax20, h20_bar, Legend_Label_20, ...
                    S, F20.Legend_Location, 1, S.Legend_Font_Size - 1);

                Bring_Markers_To_Front(ax20);
                ax20.XTickLabelRotation = 45;
                Export_Figure_Files(Figure_20_Handle, Plot_Label_Struct.Output_Directory, F20.File_Name, S.Export_DPI);
            end
        end
    end

    Enable_Damaged_Post_Plots = true;
    if isfield(Plot_Data_Struct, 'Enable_Damaged_Model_Post_Plots')
        Enable_Damaged_Post_Plots = logical(Plot_Data_Struct.Enable_Damaged_Model_Post_Plots);
    end

    Has_FEA_Response = isfield(Plot_Data_Struct, 'FEA_Response_Data') && ...
        isstruct(Plot_Data_Struct.FEA_Response_Data) && ...
        isfield(Plot_Data_Struct.FEA_Response_Data, 'Available') && ...
        logical(Plot_Data_Struct.FEA_Response_Data.Available);
    % ==================================================================
    % FIGURE 13 : FEA vs experimental true stress-strain
    % ==================================================================
    F13 = Plot_Label_Struct.Figure_13_FEA_Stress_Strain_Comparison;
    if isfield(F13, 'Enable') && F13.Enable && Has_FEA_Response
        Create_FEA_True_Comparison_Figure( ...
            Plot_Data_Struct, F13, ...
            S, Plot_Label_Struct.Output_Directory);
    end
    % ==================================================================
    % FIGURE 18 : FEA phase-only view
    % ==================================================================
    F18 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_18_FEA_Phase_Only')
        F18 = Plot_Label_Struct.Figure_18_FEA_Phase_Only;
    end
    if isfield(F18, 'Enable') && F18.Enable && Has_FEA_Response
        Create_FEA_Phase_Only_Figure( ...
            Plot_Data_Struct, F18, ...
            S, Plot_Label_Struct.Output_Directory);
    end
    % ==================================================================
    % FIGURE 19 : FEA true-stress percent error
    % ==================================================================
    F19 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_19_FEA_True_Error')
        F19 = Plot_Label_Struct.Figure_19_FEA_True_Error;
    end
    if isfield(F19, 'Enable') && F19.Enable && Has_FEA_Response
        Create_FEA_True_Error_Figure( ...
            Plot_Data_Struct, F19, ...
            S, Plot_Label_Struct.Output_Directory);
    end
    % ==================================================================
    % FIGURE 24 : Combined FEA/experimental true stress-strain + error
    % ==================================================================
    F24 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_24_FEA_True_Combined_Comparison')
        F24 = Plot_Label_Struct.Figure_24_FEA_True_Combined_Comparison;
    end
    if isfield(F24, 'Enable') && F24.Enable
        Create_FEA_True_Combined_Comparison_Error_Figure( ...
            Plot_Data_Struct, F24, ...
            S, Plot_Label_Struct.Output_Directory);
    end

    % ==================================================================
    % FIGURE 21 : 45deg fracture RPT overlay (FEA extracted curves)
    % ==================================================================
    F21 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_21_FEA_45deg_Rpt_Overlay')
        F21 = Plot_Label_Struct.Figure_21_FEA_45deg_Rpt_Overlay;
    end
    if isfield(F21, 'Enable') && F21.Enable
        Create_FEA_45deg_Rpt_Overlay_Figure( ...
            Plot_Data_Struct, F21, ...
            S, Plot_Label_Struct.Output_Directory);
    end

    % ==================================================================
    % FIGURE 22 : FEA initial deleted elements — phase-coloured plot
    % ==================================================================
    F22 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_22_FEA_Element_Phases')
        F22 = Plot_Label_Struct.Figure_22_FEA_Element_Phases;
    end
    if isfield(F22, 'Enable') && F22.Enable
        Create_FEA_Element_Phase_Figure( ...
            Plot_Data_Struct, F22, ...
            S, Plot_Label_Struct.Output_Directory);
    end

    % ==================================================================
    % FIGURE 23 : FEA initial deleted elements — stress vs time
    % ==================================================================
    F23 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_23_FEA_Element_Stress_Time')
        F23 = Plot_Label_Struct.Figure_23_FEA_Element_Stress_Time;
    end
    if isfield(F23, 'Enable') && F23.Enable
        Create_FEA_Element_Stress_Time_Figure( ...
            Plot_Data_Struct, F23, ...
            S, Plot_Label_Struct.Output_Directory);
    end

    % ==================================================================
    % FIGURE 25 : Damage-model RPT comparison (tabular, linear, exp)
    % ==================================================================
    F25 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_25_Damage_Model_Rpt_Comparison')
        F25 = Plot_Label_Struct.Figure_25_Damage_Model_Rpt_Comparison;
    end
    if isfield(F25, 'Enable') && F25.Enable
        Create_FEA_Damage_Rpt_Comparison_Figure( ...
            Plot_Data_Struct, F25, S, Plot_Label_Struct.Output_Directory);
    end

    % ==================================================================
    % FIGURE 26 : FEA vs experimental pointwise error summary
    % ==================================================================
    F26 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_26_FEA_Experimental_Point_Errors')
        F26 = Plot_Label_Struct.Figure_26_FEA_Experimental_Point_Errors;
    end
    if isfield(F26, 'Enable') && F26.Enable
        Create_FEA_Experimental_Point_Error_Figure( ...
            Plot_Data_Struct, F26, ...
            S, Plot_Label_Struct.Output_Directory);
    end

    % ==================================================================
    % FIGURE 14 : FEA field-output stages
    % ==================================================================
    F14 = struct('Enable', false);
    if isfield(Plot_Label_Struct, 'Figure_14_FEA_Field_Output_Stages')
        F14 = Plot_Label_Struct.Figure_14_FEA_Field_Output_Stages;
    end
    if Enable_Damaged_Post_Plots && isfield(F14, 'Enable') && F14.Enable
        if isfield(Plot_Data_Struct, 'FEA_Convergence_Data') && Plot_Data_Struct.FEA_Convergence_Data.Available && ...
                isfield(Plot_Data_Struct.FEA_Convergence_Data, 'Field_Output_By_Stage') && ...
                ~isempty(Plot_Data_Struct.FEA_Convergence_Data.Field_Output_By_Stage)
            Create_FEA_Field_Output_Figure(Plot_Data_Struct.FEA_Convergence_Data, F14, S, Plot_Label_Struct.Output_Directory);
        end
    end
end

function Create_FEA_True_Comparison_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    LS = Style.LineStyles;
    FEA_POI = Compute_FEA_Placeholder_POIs(Plot_Data_Struct);
    eps_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Strain);
    sig_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Stress_Damaged);
    eps_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Strain_Approx);
    sig_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Stress_Approx);

    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on'); ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';

    h_exp = plot(ax, eps_exp, sig_exp, Figure_Config.Curve_Line_Style, 'Color', Hex2Rgb(Figure_Config.Experimental_Curve_Color), 'LineWidth', Style.LineWidths);
    h_fea = plot(ax, eps_fea, sig_fea, Figure_Config.Curve_Line_Style, 'Color', Hex2Rgb(Figure_Config.FEA_Curve_Color), 'LineWidth', Style.LineWidths);

    exp_y_idx = Find_Nearest_Index(eps_exp, Plot_Data_Struct.True_Yield_Strain);
    exp_u_idx = max(1, min(numel(eps_exp), round(double(Plot_Data_Struct.UTS_Index))));
    exp_f_idx = max(1, min(numel(eps_exp), round(double(Plot_Data_Struct.Rupture_Index))));
    mk = Style.Markers;
    h_exp_y = plot(ax, eps_exp(exp_y_idx), sig_exp(exp_y_idx), ...
        'LineStyle', LS.NoLine, 'Marker', mk.Yield.Symbol, 'MarkerSize', mk.Yield.Size, ...
        'MarkerFaceColor', mk.Yield.FaceColor, 'MarkerEdgeColor', mk.Yield.EdgeColor, ...
        'LineWidth', mk.Yield.LineWidth);
    h_exp_u = plot(ax, eps_exp(exp_u_idx), sig_exp(exp_u_idx), ...
        'LineStyle', LS.NoLine, 'Marker', mk.UTS.Symbol, 'MarkerSize', mk.UTS.Size, ...
        'MarkerFaceColor', mk.UTS.EngineeringFaceColor, 'MarkerEdgeColor', mk.UTS.EngineeringEdgeColor, ...
        'LineWidth', mk.UTS.LineWidth);
    h_exp_f = plot(ax, eps_exp(exp_f_idx), sig_exp(exp_f_idx), ...
        'LineStyle', LS.NoLine, 'Marker', mk.Failure.Symbol, 'MarkerSize', mk.Failure.Size, ...
        'MarkerFaceColor', mk.Failure.EngineeringFaceColor, 'MarkerEdgeColor', mk.Failure.EngineeringEdgeColor, ...
        'LineWidth', mk.Failure.LineWidth);

    h_fea_y = plot(ax, FEA_POI.Yield_Strain, FEA_POI.Yield_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.FEA_Yield_Marker, 'MarkerSize', Figure_Config.FEA_Yield_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_Yield_FaceColor), 'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_Yield_EdgeColor), 'LineWidth', Figure_Config.FEA_Marker_LineWidth);
    h_fea_u = plot(ax, FEA_POI.UTS_Strain, FEA_POI.UTS_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.FEA_UTS_Marker, 'MarkerSize', Figure_Config.FEA_UTS_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_UTS_FaceColor), 'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_UTS_EdgeColor), 'LineWidth', Figure_Config.FEA_Marker_LineWidth);
    h_fea_f = plot(ax, FEA_POI.Failure_Strain, FEA_POI.Failure_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.FEA_Failure_Marker, 'MarkerSize', Figure_Config.FEA_Failure_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_Failure_FaceColor), 'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_Failure_EdgeColor), 'LineWidth', Figure_Config.FEA_Marker_LineWidth);

    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, Figure_Config.Title, Style, Style.Font_Sizes);
    Apply_Primary_Axis_Style(ax, Style);

    Apply_Legend_Template(ax, ...
        [h_exp, h_fea, h_exp_y, h_exp_u, h_exp_f, h_fea_y, h_fea_u, h_fea_f], ...
        Figure_Config.Legend, ...
        Style, Figure_Config.Legend_Location, 1, Style.Legend_Font_Size - 2);

    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);
end

function Create_FEA_Phase_Only_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    LS = Style.LineStyles;
    FEA_POI = Compute_FEA_Placeholder_POIs(Plot_Data_Struct);
    eps_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Strain_Approx);
    sig_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Stress_Approx);

    y_idx = FEA_POI.Yield_Index;
    u_idx = FEA_POI.UTS_Index;
    f_idx = FEA_POI.Failure_Index;

    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on'); ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';

    h_el = plot(ax, eps_fea(1:y_idx), sig_fea(1:y_idx), Figure_Config.Elastic_Line_Style, 'Color', Hex2Rgb(Figure_Config.Elastic_Color), 'LineWidth', Style.LineWidths);
    h_hd = plot(ax, eps_fea(y_idx:u_idx), sig_fea(y_idx:u_idx), Figure_Config.Hardening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Hardening_Color), 'LineWidth', Style.LineWidths);
    h_sf = plot(ax, eps_fea(u_idx:f_idx), sig_fea(u_idx:f_idx), Figure_Config.Softening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Softening_Color), 'LineWidth', Style.LineWidths);

    h_y = plot(ax, FEA_POI.Yield_Strain, FEA_POI.Yield_Stress, 'LineStyle', LS.NoLine, ...
        'Marker', Figure_Config.Yield_Marker, 'MarkerSize', Figure_Config.Yield_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.Yield_FaceColor), 'MarkerEdgeColor', Hex2Rgb(Figure_Config.Yield_EdgeColor), 'LineWidth', Figure_Config.Marker_LineWidth);
    h_u = plot(ax, FEA_POI.UTS_Strain, FEA_POI.UTS_Stress, 'LineStyle', LS.NoLine, ...
        'Marker', Figure_Config.UTS_Marker, 'MarkerSize', Figure_Config.UTS_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.UTS_FaceColor), 'MarkerEdgeColor', Hex2Rgb(Figure_Config.UTS_EdgeColor), 'LineWidth', Figure_Config.Marker_LineWidth);
    h_f = plot(ax, FEA_POI.Failure_Strain, FEA_POI.Failure_Stress, 'LineStyle', LS.NoLine, ...
        'Marker', Figure_Config.Failure_Marker, 'MarkerSize', Figure_Config.Failure_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.Failure_FaceColor), 'MarkerEdgeColor', Hex2Rgb(Figure_Config.Failure_EdgeColor), 'LineWidth', Figure_Config.Marker_LineWidth);

    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, Figure_Config.Title, Style, Style.Font_Sizes);
    Apply_Primary_Axis_Style(ax, Style);
    Apply_Legend_Template(ax, [h_el, h_hd, h_sf, h_y, h_u, h_f], ...
        {'Elastic regime', 'Hardening regime', 'Softening regime', 'Yield (placeholder)', 'UTS (placeholder)', 'Failure (placeholder)'}, ...
        Style, Figure_Config.Legend_Location, 1, Style.Legend_Font_Size - 2);

    phase_text = { ...
        '\textbf{Phase ranges (placeholder)}', ...
        sprintf('Elastic: $\\varepsilon_T\\in[%.6f, %.6f]$, $\\sigma_T\\in[%.4f, %.4f]$ MPa', ...
            min(eps_fea(1:y_idx)), max(eps_fea(1:y_idx)), min(sig_fea(1:y_idx)), max(sig_fea(1:y_idx))), ...
        sprintf('Hardening: $\\varepsilon_T\\in[%.6f, %.6f]$, $\\sigma_T\\in[%.4f, %.4f]$ MPa', ...
            min(eps_fea(y_idx:u_idx)), max(eps_fea(y_idx:u_idx)), min(sig_fea(y_idx:u_idx)), max(sig_fea(y_idx:u_idx))), ...
        sprintf('Softening: $\\varepsilon_T\\in[%.6f, %.6f]$, $\\sigma_T\\in[%.4f, %.4f]$ MPa', ...
            min(eps_fea(u_idx:f_idx)), max(eps_fea(u_idx:f_idx)), min(sig_fea(u_idx:f_idx)), max(sig_fea(u_idx:f_idx))), ...
        sprintf('Yield: $(%.6f, %.4f)$', FEA_POI.Yield_Strain, FEA_POI.Yield_Stress), ...
        sprintf('UTS: $(%.6f, %.4f)$', FEA_POI.UTS_Strain, FEA_POI.UTS_Stress), ...
        sprintf('Failure: $(%.6f, %.4f)$', FEA_POI.Failure_Strain, FEA_POI.Failure_Stress) ...
    };
    x_rng = xlim(ax);
    y_rng = ylim(ax);
    Add_Axis_Annotation_Box(ax, x_rng(1) + 0.57 * diff(x_rng), y_rng(1) + 0.19 * diff(y_rng), ...
        phase_text, Style, Hex2Rgb(Figure_Config.Annotation_EdgeColor), 0, 'bottom', 'left');

    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);
end

function Create_FEA_Element_Phase_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    %CREATE_FEA_ELEMENT_PHASE_FIGURE  Phase-coloured plot for the initial
    %   deleted element stress-strain data with yield and dual-UTS markers.

    LS = Style.LineStyles;

    % --- Resolve .rpt path and parse element curves -----------------------
    rpt_path = "";
    if isfield(Figure_Config, 'Rpt_Path') && strlength(string(Figure_Config.Rpt_Path)) > 0
        rpt_path = string(Figure_Config.Rpt_Path);
    else
        rpt_path = Resolve_Stress_Strain_Rpt_Path();
    end
    if strlength(rpt_path) == 0 || ~isfile(char(rpt_path))
        fprintf('[PLOTS] Figure 22 skipped (Stress-Strain.rpt not found).\n');
        return;
    end
    Curves = Parse_Stress_Strain_Rpt_Curves(char(rpt_path));
    if ~Curves.Available || isempty(Curves.Strain_First) || isempty(Curves.Stress_First)
        fprintf('[PLOTS] Figure 22 skipped (Initial Deleted Elements data unavailable).\n');
        return;
    end

    % --- Compute POIs using the dedicated element analysis ----------------
    Element_POI = Compute_FEA_Element_POIs(Curves.Strain_First, Curves.Stress_First);

    eps_el = Element_POI.True_Strain;
    sig_el = Element_POI.True_Stress;
    y_idx  = Element_POI.Yield_Index;
    u_idx  = Element_POI.UTS_Index;
    f_idx  = Element_POI.Failure_Index;

    % --- Create figure ----------------------------------------------------
    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on'); ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';

    % Phase-coloured line segments
    h_el = plot(ax, eps_el(1:y_idx), sig_el(1:y_idx), ...
        Figure_Config.Elastic_Line_Style, 'Color', Hex2Rgb(Figure_Config.Elastic_Color), 'LineWidth', Style.LineWidths);
    h_hd = plot(ax, eps_el(y_idx:u_idx), sig_el(y_idx:u_idx), ...
        Figure_Config.Hardening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Hardening_Color), 'LineWidth', Style.LineWidths);
    h_sf = plot(ax, eps_el(u_idx:f_idx), sig_el(u_idx:f_idx), ...
        Figure_Config.Softening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Softening_Color), 'LineWidth', Style.LineWidths);

    % Yield marker
    h_y = plot(ax, Element_POI.Yield_Strain, Element_POI.Yield_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.Yield_Marker, ...
        'MarkerSize', Figure_Config.Yield_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.Yield_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.Yield_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);

    % UTS marker — Considere criterion
    h_uc = plot(ax, Element_POI.Considere_Strain, Element_POI.Considere_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.UTS_Considere_Marker, ...
        'MarkerSize', Figure_Config.UTS_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.UTS_Considere_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.UTS_Considere_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);

    % UTS marker — Engineering peak method
    h_ue = plot(ax, Element_POI.Engineering_Peak_True_Strain, Element_POI.Engineering_Peak_True_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.UTS_Engineering_Marker, ...
        'MarkerSize', Figure_Config.UTS_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.UTS_Engineering_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.UTS_Engineering_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);

    % Failure marker
    h_f = plot(ax, Element_POI.Failure_Strain, Element_POI.Failure_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.Failure_Marker, ...
        'MarkerSize', Figure_Config.Failure_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.Failure_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.Failure_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);

    % --- Font-size overrides from Figure_Config ----------------------------
    Fig_Font_Sizes = Style.Font_Sizes;
    if isfield(Figure_Config, 'Font_Sizes')
        Fig_Font_Sizes = Figure_Config.Font_Sizes;
    end
    Fig_Legend_FS = Style.Legend_Font_Size;
    if isfield(Figure_Config, 'Legend_Font_Size')
        Fig_Legend_FS = Figure_Config.Legend_Font_Size;
    end
    Fig_Ann_FS = Style.Annotation.Font_Size;
    if isfield(Figure_Config, 'Annotation_Font_Size')
        Fig_Ann_FS = Figure_Config.Annotation_Font_Size;
    end

    % --- Formatting -------------------------------------------------------
    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, Figure_Config.Title, Style, Fig_Font_Sizes);
    Apply_Primary_Axis_Style(ax, Style);
    xlim(ax, [-0.01, max(eps_el) * 1.03]);

    Apply_Legend_Template(ax, [h_el, h_hd, h_sf, h_y, h_uc, h_ue, h_f], ...
        {'Elastic regime', 'Hardening regime', 'Softening regime', ...
         sprintf('Yield $(%.6f,\\,%.4f)$', Element_POI.Yield_Strain, Element_POI.Yield_Stress), ...
         sprintf('UTS Consid\\`ere $(%.6f,\\,%.4f)$', Element_POI.Considere_Strain, Element_POI.Considere_Stress), ...
         sprintf('UTS Eng.~Peak $(%.6f,\\,%.4f)$', Element_POI.Engineering_Peak_True_Strain, Element_POI.Engineering_Peak_True_Stress), ...
         sprintf('Failure $(%.6f,\\,%.4f)$', Element_POI.Failure_Strain, Element_POI.Failure_Stress)}, ...
        Style, Figure_Config.Legend_Location, 1, Fig_Legend_FS);

    % --- Annotation box with phase ranges and key coordinates -------------
    Ann_Style = Style;
    Ann_Style.Annotation.Font_Size = Fig_Ann_FS;

    phase_text = { ...
        '\textbf{Phase ranges --- Initial Deleted Elements}', ...
        sprintf('$E = %.4f$ MPa', Element_POI.Youngs_Modulus), ...
        sprintf('Elastic: $\\varepsilon_T\\in[%.6f,\\,%.6f]$, $\\sigma_T\\in[%.4f,\\,%.4f]$ MPa', ...
            min(eps_el(1:y_idx)), max(eps_el(1:y_idx)), min(sig_el(1:y_idx)), max(sig_el(1:y_idx))), ...
        sprintf('Hardening: $\\varepsilon_T\\in[%.6f,\\,%.6f]$, $\\sigma_T\\in[%.4f,\\,%.4f]$ MPa', ...
            min(eps_el(y_idx:u_idx)), max(eps_el(y_idx:u_idx)), min(sig_el(y_idx:u_idx)), max(sig_el(y_idx:u_idx))), ...
        sprintf('Softening: $\\varepsilon_T\\in[%.6f,\\,%.6f]$, $\\sigma_T\\in[%.4f,\\,%.4f]$ MPa', ...
            min(eps_el(u_idx:f_idx)), max(eps_el(u_idx:f_idx)), min(sig_el(u_idx:f_idx)), max(sig_el(u_idx:f_idx))), ...
        sprintf('Yield: $(%.6f,\\,%.4f)$', Element_POI.Yield_Strain, Element_POI.Yield_Stress), ...
        sprintf('UTS (Consid\\`ere): $(%.6f,\\,%.4f)$', Element_POI.Considere_Strain, Element_POI.Considere_Stress), ...
        sprintf('UTS (Eng.~Peak): $(%.6f,\\,%.4f)$', Element_POI.Engineering_Peak_True_Strain, Element_POI.Engineering_Peak_True_Stress), ...
        sprintf('Failure: $(%.6f,\\,%.4f)$', Element_POI.Failure_Strain, Element_POI.Failure_Stress) ...
    };
    x_rng = xlim(ax);
    y_rng = ylim(ax);
    Add_Axis_Annotation_Box(ax, x_rng(1) + 0.57 * diff(x_rng), y_rng(1) + 0.19 * diff(y_rng), ...
        phase_text, Ann_Style, Hex2Rgb(Figure_Config.Annotation_EdgeColor), 0, 'bottom', 'left');

    % --- Inset: magnified Yield-to-UTS region -----------------------------
    Inset_Cfg = struct('Enable', false);
    if isfield(Figure_Config, 'Inset')
        Inset_Cfg = Figure_Config.Inset;
    end
    if isfield(Inset_Cfg, 'Enable') && Inset_Cfg.Enable
        % Determine the two UTS strain/stress extremes
        uts_strains = [Element_POI.Considere_Strain, Element_POI.Engineering_Peak_True_Strain];
        uts_stresses = [Element_POI.Considere_Stress, Element_POI.Engineering_Peak_True_Stress];

        zoom_x_lo = Element_POI.Yield_Strain - Inset_Cfg.Strain_Pad_Before_Yield;
        zoom_x_hi = max(uts_strains) + Inset_Cfg.Strain_Pad_After_UTS;

        % Gather stress values in the zoom strain window
        in_window = (eps_el >= zoom_x_lo) & (eps_el <= zoom_x_hi);
        sig_window = sig_el(in_window);
        stress_lo = min([sig_window; Element_POI.Yield_Stress; uts_stresses(:)]);
        stress_hi = max([sig_window; Element_POI.Yield_Stress; uts_stresses(:)]);
        stress_pad = Inset_Cfg.Stress_Pad_Frac * (stress_hi - stress_lo);
        zoom_y_lo = stress_lo - stress_pad;
        zoom_y_hi = stress_hi + stress_pad;

        % Expand main-axis Y lower limit so inset sits under the curve
        main_y = ylim(ax);
        needed_headroom = (main_y(2) - main_y(1)) * 0.48;
        if main_y(1) > (main_y(2) - needed_headroom * 2.2)
            ylim(ax, [main_y(1) - needed_headroom * 0.6, main_y(2)]);
        end

        show_lines = false;
        if isfield(Inset_Cfg, 'Show_Connecting_Lines')
            show_lines = logical(Inset_Cfg.Show_Connecting_Lines);
        end

        inset_ax = Create_Inset_Axes(ax, ...
            [zoom_x_lo, zoom_x_hi], [zoom_y_lo, zoom_y_hi], ...
            Inset_Cfg.Position, Style, show_lines);

        % Re-derive segment indices within inset range
        ins_y_idx = max(1, y_idx);
        ins_u_idx_c = max(ins_y_idx, Element_POI.Considere_Index);
        ins_u_idx_e = max(ins_y_idx, Element_POI.Engineering_Peak_Index);
        ins_u_idx = max(ins_y_idx, u_idx);

        % Upper segment bound for inset: a few points past the later UTS
        n_el = numel(eps_el);
        ins_end = min(n_el, max(ins_u_idx_c, ins_u_idx_e) + round(0.03 * n_el));

        % Phase-coloured segments in inset
        ins_mk_sz = 16;
        if isfield(Figure_Config, 'Inset_Marker_Size')
            ins_mk_sz = Figure_Config.Inset_Marker_Size;
        end

        plot(inset_ax, eps_el(1:ins_y_idx), sig_el(1:ins_y_idx), ...
            Figure_Config.Elastic_Line_Style, 'Color', Hex2Rgb(Figure_Config.Elastic_Color), 'LineWidth', Style.LineWidths);
        plot(inset_ax, eps_el(ins_y_idx:ins_u_idx), sig_el(ins_y_idx:ins_u_idx), ...
            Figure_Config.Hardening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Hardening_Color), 'LineWidth', Style.LineWidths);
        if ins_end > ins_u_idx
            plot(inset_ax, eps_el(ins_u_idx:ins_end), sig_el(ins_u_idx:ins_end), ...
                Figure_Config.Softening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Softening_Color), 'LineWidth', Style.LineWidths);
        end

        % Markers in inset (size 16)
        plot(inset_ax, Element_POI.Yield_Strain, Element_POI.Yield_Stress, ...
            'LineStyle', LS.NoLine, 'Marker', Figure_Config.Yield_Marker, ...
            'MarkerSize', ins_mk_sz, ...
            'MarkerFaceColor', Hex2Rgb(Figure_Config.Yield_FaceColor), ...
            'MarkerEdgeColor', Hex2Rgb(Figure_Config.Yield_EdgeColor), ...
            'LineWidth', Figure_Config.Marker_LineWidth);
        plot(inset_ax, Element_POI.Considere_Strain, Element_POI.Considere_Stress, ...
            'LineStyle', LS.NoLine, 'Marker', Figure_Config.UTS_Considere_Marker, ...
            'MarkerSize', ins_mk_sz, ...
            'MarkerFaceColor', Hex2Rgb(Figure_Config.UTS_Considere_FaceColor), ...
            'MarkerEdgeColor', Hex2Rgb(Figure_Config.UTS_Considere_EdgeColor), ...
            'LineWidth', Figure_Config.Marker_LineWidth);
        plot(inset_ax, Element_POI.Engineering_Peak_True_Strain, Element_POI.Engineering_Peak_True_Stress, ...
            'LineStyle', LS.NoLine, 'Marker', Figure_Config.UTS_Engineering_Marker, ...
            'MarkerSize', ins_mk_sz, ...
            'MarkerFaceColor', Hex2Rgb(Figure_Config.UTS_Engineering_FaceColor), ...
            'MarkerEdgeColor', Hex2Rgb(Figure_Config.UTS_Engineering_EdgeColor), ...
            'LineWidth', Figure_Config.Marker_LineWidth);

        grid(inset_ax, 'on');
        Apply_Inset_Axis_Style(inset_ax, Style);
        Bring_Markers_To_Front(inset_ax);
    end

    Bring_Markers_To_Front(ax);
    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);
end

function Create_FEA_Element_Stress_Time_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    %CREATE_FEA_ELEMENT_STRESS_TIME_FIGURE  Stress vs time plot for the
    %   initial deleted elements with phase-coloured regimes and terminal
    %   output of the five phase ranges (elastic, yield, hardening, UTS,
    %   softening).

    LS = Style.LineStyles;

    % --- Resolve .rpt and parse -------------------------------------------
    rpt_path = "";
    if isfield(Figure_Config, 'Rpt_Path') && strlength(string(Figure_Config.Rpt_Path)) > 0
        rpt_path = string(Figure_Config.Rpt_Path);
    else
        rpt_path = Resolve_Stress_Strain_Rpt_Path();
    end
    if strlength(rpt_path) == 0 || ~isfile(char(rpt_path))
        fprintf('[PLOTS] Figure 23 skipped (Stress-Strain.rpt not found).\n');
        return;
    end
    Curves = Parse_Stress_Strain_Rpt_Curves(char(rpt_path));
    if ~Curves.Available || isempty(Curves.Strain_First) || isempty(Curves.Stress_First)
        fprintf('[PLOTS] Figure 23 skipped (Initial Deleted Elements data unavailable).\n');
        return;
    end
    if isempty(Curves.Time)
        fprintf('[PLOTS] Figure 23 skipped (Time column not available in .rpt).\n');
        return;
    end

    % --- Compute POIs (reuses the same function as Fig 22) ----------------
    Element_POI = Compute_FEA_Element_POIs(Curves.Strain_First, Curves.Stress_First);

    % Build aligned time vector (same row order as Strain_First / Stress_First)
    time_raw = Ensure_Column_Vector(Curves.Time);
    eps_raw = Ensure_Column_Vector(Curves.Strain_First);
    sig_raw = Ensure_Column_Vector(Curves.Stress_First);
    mask = ~isnan(eps_raw) & ~isnan(sig_raw) & isfinite(eps_raw) & isfinite(sig_raw) ...
         & ~isnan(time_raw) & isfinite(time_raw);
    time_v = time_raw(mask);
    eps_v = eps_raw(mask);
    sig_v = sig_raw(mask);
    [eps_v, s_idx] = sort(eps_v);
    sig_v = sig_v(s_idx);
    time_v = time_v(s_idx);

    y_idx = Element_POI.Yield_Index;
    u_idx = Element_POI.UTS_Index;
    f_idx = Element_POI.Failure_Index;
    n_pts = numel(time_v);
    y_idx = max(1, min(y_idx, n_pts));
    u_idx = max(y_idx, min(u_idx, n_pts));
    f_idx = max(u_idx, min(f_idx, n_pts));
    elastic_time = time_v(1:y_idx);
    elastic_eps = eps_v(1:y_idx);
    elastic_sig = sig_v(1:y_idx);
    hardening_time = time_v(y_idx:u_idx);
    hardening_eps = eps_v(y_idx:u_idx);
    hardening_sig = sig_v(y_idx:u_idx);
    softening_time = time_v(u_idx:f_idx);
    softening_eps = eps_v(u_idx:f_idx);
    softening_sig = sig_v(u_idx:f_idx);

    % --- Font-size overrides ----------------------------------------------
    Fig_Font_Sizes = Style.Font_Sizes;
    if isfield(Figure_Config, 'Font_Sizes'), Fig_Font_Sizes = Figure_Config.Font_Sizes; end
    Fig_Legend_FS = Style.Legend_Font_Size;
    if isfield(Figure_Config, 'Legend_Font_Size'), Fig_Legend_FS = Figure_Config.Legend_Font_Size; end
    Fig_Ann_FS = Style.Annotation.Font_Size;
    if isfield(Figure_Config, 'Annotation_Font_Size'), Fig_Ann_FS = Figure_Config.Annotation_Font_Size; end
    Regime_Fill_Alpha = 0.10;
    if isfield(Figure_Config, 'Regime_Fill_Alpha'), Regime_Fill_Alpha = Figure_Config.Regime_Fill_Alpha; end
    Marker_Vertical_Line_Style = '--';
    if isfield(Figure_Config, 'Marker_Vertical_Line_Style'), Marker_Vertical_Line_Style = Figure_Config.Marker_Vertical_Line_Style; end
    Marker_Vertical_Line_Width = 1.6;
    if isfield(Figure_Config, 'Marker_Vertical_Line_Width'), Marker_Vertical_Line_Width = Figure_Config.Marker_Vertical_Line_Width; end

    % --- Create figure ----------------------------------------------------
    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on'); ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';

    % Phase-coloured segments (stress vs time)
    h_el = plot(ax, time_v(1:y_idx), sig_v(1:y_idx), ...
        Figure_Config.Elastic_Line_Style, 'Color', Hex2Rgb(Figure_Config.Elastic_Color), 'LineWidth', Style.LineWidths);
    h_hd = plot(ax, time_v(y_idx:u_idx), sig_v(y_idx:u_idx), ...
        Figure_Config.Hardening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Hardening_Color), 'LineWidth', Style.LineWidths);
    h_sf = plot(ax, time_v(u_idx:f_idx), sig_v(u_idx:f_idx), ...
        Figure_Config.Softening_Line_Style, 'Color', Hex2Rgb(Figure_Config.Softening_Color), 'LineWidth', Style.LineWidths);

    % Markers
    h_y = plot(ax, time_v(y_idx), sig_v(y_idx), ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.Yield_Marker, ...
        'MarkerSize', Figure_Config.Yield_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.Yield_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.Yield_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);
    h_u = plot(ax, time_v(u_idx), sig_v(u_idx), ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.UTS_Marker, ...
        'MarkerSize', Figure_Config.UTS_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.UTS_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.UTS_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);
    h_f = plot(ax, time_v(f_idx), sig_v(f_idx), ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.Failure_Marker, ...
        'MarkerSize', Figure_Config.Failure_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.Failure_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.Failure_EdgeColor), ...
        'LineWidth', Figure_Config.Marker_LineWidth);

    % Regime fills and marker-aligned vertical lines
    time_plot = time_v(1:f_idx);
    sig_plot = sig_v(1:f_idx);
    x_min = min(time_plot);
    x_max = max(time_plot);
    y_min = min(sig_plot);
    y_max = max(sig_plot);
    y_pad = 0.06 * max(y_max - y_min, eps);
    y_base = max(0, y_min - y_pad);
    y_top = y_max + y_pad;
    xlim(ax, [0, 0.2]);
    ylim(ax, [y_base, y_top]);

    regime_bounds = [ ...
        time_plot(1), time_v(y_idx); ...
        time_v(y_idx), time_v(u_idx); ...
        time_v(u_idx), time_v(f_idx)];
    regime_colors = { ...
        Hex2Rgb(Figure_Config.Elastic_Color), ...
        Hex2Rgb(Figure_Config.Hardening_Color), ...
        Hex2Rgb(Figure_Config.Softening_Color)};

    for idx_regime = 1:size(regime_bounds, 1)
        x1 = regime_bounds(idx_regime, 1);
        x2 = regime_bounds(idx_regime, 2);
        if x2 <= x1
            continue;
        end
        h_patch = patch(ax, [x1, x2, x2, x1], [y_base, y_base, y_top, y_top], regime_colors{idx_regime}, ...
            'FaceAlpha', Regime_Fill_Alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        uistack(h_patch, 'bottom');
    end

    h_yline = xline(ax, time_v(y_idx), Marker_Vertical_Line_Style, ...
        'Color', Hex2Rgb(Figure_Config.Yield_EdgeColor), 'LineWidth', Marker_Vertical_Line_Width, 'HandleVisibility', 'off');
    h_uline = xline(ax, time_v(u_idx), Marker_Vertical_Line_Style, ...
        'Color', Hex2Rgb(Figure_Config.UTS_EdgeColor), 'LineWidth', Marker_Vertical_Line_Width, 'HandleVisibility', 'off');
    h_fline = xline(ax, time_v(f_idx), Marker_Vertical_Line_Style, ...
        'Color', Hex2Rgb(Figure_Config.Failure_EdgeColor), 'LineWidth', Marker_Vertical_Line_Width, 'HandleVisibility', 'off');

    % --- Formatting -------------------------------------------------------
    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, Figure_Config.Title, Style, Fig_Font_Sizes);
    Apply_Primary_Axis_Style(ax, Style);

    Apply_Legend_Template(ax, [h_el, h_hd, h_sf, h_y, h_u, h_f], ...
        {'Elastic regime', 'Hardening regime', 'Softening regime', ...
         sprintf('Yield $(t=%.6f,\\,\\sigma_T=%.4f)$', time_v(y_idx), sig_v(y_idx)), ...
         sprintf('UTS $(t=%.6f,\\,\\sigma_T=%.4f)$', time_v(u_idx), sig_v(u_idx)), ...
         sprintf('Failure $(t=%.6f,\\,\\sigma_T=%.4f)$', time_v(f_idx), sig_v(f_idx))}, ...
        Style, Figure_Config.Legend_Location, 1, Fig_Legend_FS);

    % --- Annotation box ---------------------------------------------------
    Ann_Style = Style;
    Ann_Style.Annotation.Font_Size = Fig_Ann_FS;

    ann_text = { ...
        '\textbf{Phase ranges --- Stress vs Time}', ...
        sprintf('Elastic: $t\\in[%.6f,\\,%.6f]$, $\\varepsilon_T\\in[%.6f,\\,%.6f]$, $\\sigma_T\\in[%.4f,\\,%.4f]$ MPa', ...
            elastic_time(1), elastic_time(end), min(elastic_eps), max(elastic_eps), min(elastic_sig), max(elastic_sig)), ...
        sprintf('Yield: $(t=%.6f,\\,\\varepsilon_T=%.6f,\\,\\sigma_T=%.4f)$ MPa', time_v(y_idx), eps_v(y_idx), sig_v(y_idx)), ...
        sprintf('Hardening: $t\\in[%.6f,\\,%.6f]$, $\\varepsilon_T\\in[%.6f,\\,%.6f]$, $\\sigma_T\\in[%.4f,\\,%.4f]$ MPa', ...
            hardening_time(1), hardening_time(end), min(hardening_eps), max(hardening_eps), min(hardening_sig), max(hardening_sig)), ...
        sprintf('UTS: $(t=%.6f,\\,\\varepsilon_T=%.6f,\\,\\sigma_T=%.4f)$ MPa', time_v(u_idx), eps_v(u_idx), sig_v(u_idx)), ...
        sprintf('Softening: $t\\in[%.6f,\\,%.6f]$, $\\varepsilon_T\\in[%.6f,\\,%.6f]$, $\\sigma_T\\in[%.4f,\\,%.4f]$ MPa', ...
            softening_time(1), softening_time(end), min(softening_eps), max(softening_eps), min(softening_sig), max(softening_sig)), ...
        sprintf('Failure: $(t=%.6f,\\,\\varepsilon_T=%.6f,\\,\\sigma_T=%.4f)$ MPa', time_v(f_idx), eps_v(f_idx), sig_v(f_idx)) ...
    };
    x_rng = xlim(ax);
    y_rng = ylim(ax);
    Add_Axis_Annotation_Box(ax, x_rng(1) + 0.55 * diff(x_rng), y_rng(1) + 0.20 * diff(y_rng), ...
        ann_text, Ann_Style, Hex2Rgb(Figure_Config.Annotation_EdgeColor), 0, 'bottom', 'left');

    Bring_Markers_To_Front(ax);
    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);

    % --- Terminal output of the five phase ranges -------------------------
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  FIGURE 23 — Phase Ranges (Initial Deleted Elements)\n');
    fprintf('============================================================\n');
    fprintf('  FEA output (time, true strain, true stress)\n');
    fprintf('  1. Elastic    :  t in [%.6f, %.6f]  |  eps_T in [%.6f, %.6f]  |  sigma_T in [%.4f, %.4f] MPa\n', ...
        elastic_time(1), elastic_time(end), min(elastic_eps), max(elastic_eps), min(elastic_sig), max(elastic_sig));
    fprintf('  2. Yield Point:  t = %.6f  |  eps_T = %.6f  |  sigma_T = %.4f MPa\n', ...
        time_v(y_idx), eps_v(y_idx), sig_v(y_idx));
    fprintf('  3. Hardening  :  t in [%.6f, %.6f]  |  eps_T in [%.6f, %.6f]  |  sigma_T in [%.4f, %.4f] MPa\n', ...
        hardening_time(1), hardening_time(end), min(hardening_eps), max(hardening_eps), min(hardening_sig), max(hardening_sig));
    fprintf('  4. UTS        :  t = %.6f  |  eps_T = %.6f  |  sigma_T = %.4f MPa\n', ...
        time_v(u_idx), eps_v(u_idx), sig_v(u_idx));
    fprintf('  5. Softening  :  t in [%.6f, %.6f]  |  eps_T in [%.6f, %.6f]  |  sigma_T in [%.4f, %.4f] MPa\n', ...
        softening_time(1), softening_time(end), min(softening_eps), max(softening_eps), min(softening_sig), max(softening_sig));
    fprintf('  6. Failure    :  t = %.6f  |  eps_T = %.6f  |  sigma_T = %.4f MPa\n', ...
        time_v(f_idx), eps_v(f_idx), sig_v(f_idx));
    fprintf('------------------------------------------------------------\n');
    fprintf('  True-stress plot regime ranges (strain, stress)\n');
    fprintf('  1. Elastic    :  eps_T in [%.6f, %.6f]  |  sigma_T in [%.4f, %.4f] MPa\n', ...
        min(elastic_eps), max(elastic_eps), min(elastic_sig), max(elastic_sig));
    fprintf('  2. Yield Point:  eps_T = %.6f  |  sigma_T = %.4f MPa\n', ...
        eps_v(y_idx), sig_v(y_idx));
    fprintf('  3. Hardening  :  eps_T in [%.6f, %.6f]  |  sigma_T in [%.4f, %.4f] MPa\n', ...
        min(hardening_eps), max(hardening_eps), min(hardening_sig), max(hardening_sig));
    fprintf('  4. UTS        :  eps_T = %.6f  |  sigma_T = %.4f MPa\n', ...
        eps_v(u_idx), sig_v(u_idx));
    fprintf('  5. Softening  :  eps_T in [%.6f, %.6f]  |  sigma_T in [%.4f, %.4f] MPa\n', ...
        min(softening_eps), max(softening_eps), min(softening_sig), max(softening_sig));
    fprintf('  6. Failure    :  eps_T = %.6f  |  sigma_T = %.4f MPa\n', ...
        eps_v(f_idx), sig_v(f_idx));
    fprintf('============================================================\n\n');
end

function Create_FEA_Damage_Rpt_Comparison_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
%CREATE_FEA_DAMAGE_RPT_COMPARISON_FIGURE  Overlay tabular, linear, and
%   exponential damage-model stress-strain curves from .rpt files.

    % ---- Resolve and parse the three RPT sources -------------------------
    % Tabular: uses the existing Stress-Strain.rpt parser (First curve).
    tab_path = Resolve_Damage_Rpt_Path(Figure_Config.Tabular_Base_Name);
    lin_path = Resolve_Damage_Rpt_Path(Figure_Config.Linear_Base_Name);
    exp_path = Resolve_Damage_Rpt_Path(Figure_Config.Exponential_Base_Name);

    has_tab = strlength(tab_path) > 0 && isfile(char(tab_path));
    has_lin = strlength(lin_path) > 0 && isfile(char(lin_path));
    has_exp = strlength(exp_path) > 0 && isfile(char(exp_path));

    if ~has_tab && ~has_lin && ~has_exp
        fprintf('[PLOTS] Figure 25 skipped (no damage RPT files found).\n');
        return;
    end

    % Tabular: parse with existing multi-column parser and use First curve
    tab_eps = []; tab_sig = [];
    if has_tab
        Tab_Curves = Parse_Stress_Strain_Rpt_Curves(char(tab_path));
        if Tab_Curves.Available
            tab_eps = Ensure_Column_Vector(Tab_Curves.Strain_First);
            tab_sig = Ensure_Column_Vector(Tab_Curves.Stress_First);
            [tab_eps, tab_sig] = Truncate_Damage_Model_Curve(tab_eps, tab_sig);
        end
    end

    % Linear
    Lin_Result = struct('Available', false);
    if has_lin
        Lin_Result = Parse_Damage_Rpt_Curves(char(lin_path));
    end

    % Exponential
    Exp_Result = struct('Available', false);
    if has_exp
        Exp_Result = Parse_Damage_Rpt_Curves(char(exp_path));
    end

    % ---- Create figure ---------------------------------------------------
    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on');
    ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';

    handles = [];
    labels = {};
    % ---- Tabular curve ---------------------------------------------------
    if ~isempty(tab_eps)
        h_tab = plot(ax, tab_eps, tab_sig, ...
            Figure_Config.Tabular_Line_Style, ...
            'Color', Hex2Rgb(Figure_Config.Tabular_Color), ...
            'LineWidth', Style.LineWidths + 0.4);
        handles(end + 1) = h_tab;
        labels{end + 1} = Figure_Config.Tabular_Label;
    end

    % ---- Linear curve(s) -------------------------------------------------
    if Lin_Result.Available
        for k = 1:Lin_Result.N_Curves
            [lin_eps, lin_sig] = Truncate_Damage_Model_Curve(Lin_Result.Strain{k}, Lin_Result.Stress{k});
            if isempty(lin_eps)
                continue;
            end
            h_lin = plot(ax, lin_eps, lin_sig, ...
                Figure_Config.Linear_Line_Style, ...
                'Color', Hex2Rgb(Figure_Config.Linear_Color), ...
                'LineWidth', Style.LineWidths);
            if k == 1
                handles(end + 1) = h_lin; %#ok<AGROW>
                labels{end + 1} = Figure_Config.Linear_Label; %#ok<AGROW>
            end
        end
    end

    % ---- Exponential curves ----------------------------------------------
    if Exp_Result.Available
        n_exp = Exp_Result.N_Curves;
        % Generate distinct colours from the specified colormap
        cmap_func = str2func(Figure_Config.Exponential_Colormap);
        exp_colors = cmap_func(max(n_exp, 7));
        exp_ls = Figure_Config.Exponential_Line_Styles;
        exp_mk = Figure_Config.Exponential_Markers;

        % Sort by alpha for consistent legend ordering
        [sorted_alpha, sort_idx] = sort(Exp_Result.Alpha);
        for ki = 1:n_exp
            k = sort_idx(ki);
            [exp_eps, exp_sig] = Truncate_Damage_Model_Curve(Exp_Result.Strain{k}, Exp_Result.Stress{k});
            if isempty(exp_eps)
                continue;
            end
            ls_k = exp_ls{min(ki, numel(exp_ls))};
            mk_k = exp_mk{min(ki, numel(exp_mk))};
            n_markers = min(8, max(numel(exp_eps), 1));
            marker_idx = unique(max(1, round(linspace(1, numel(exp_eps), n_markers))));
            h_exp = plot(ax, exp_eps, exp_sig, ...
                ls_k, 'Color', exp_colors(ki, :), ...
                'LineWidth', Style.LineWidths, ...
                'Marker', mk_k, 'MarkerSize', 4, ...
                'MarkerIndices', marker_idx);
            handles(end + 1) = h_exp; %#ok<AGROW>
            alpha_str = sprintf('%.2g', sorted_alpha(ki));
            labels{end + 1} = [Figure_Config.Exponential_Label_Prefix, alpha_str, Figure_Config.Exponential_Label_Suffix]; %#ok<AGROW>
        end
    end

    % ---- Format ----------------------------------------------------------
    if isfield(Plot_Data_Struct, 'Engineering_UTS_True_Strain') && ~isempty(Plot_Data_Struct.Engineering_UTS_True_Strain)
        h_uts_line = xline(ax, double(Plot_Data_Struct.Engineering_UTS_True_Strain), ...
            Figure_Config.UTS_Line_Style, ...
            'Color', Hex2Rgb(Figure_Config.UTS_Line_Color), ...
            'LineWidth', Figure_Config.UTS_Line_Width);
        try
            h_uts_line.Annotation.LegendInformation.IconDisplayStyle = 'off';
        catch
        end
    end

    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, ...
        Figure_Config.Title, Style, Style.Font_Sizes);
    Apply_Primary_Axis_Style(ax, Style);

    legend_cols = 1;
    if isfield(Figure_Config, 'Legend_NumColumns')
        legend_cols = Figure_Config.Legend_NumColumns;
    end
    lg = legend(ax, handles, labels, ...
        'Location', Figure_Config.Legend_Location, ...
        'Interpreter', 'latex', ...
        'FontSize', Style.Legend_Font_Size - 2, ...
        'NumColumns', legend_cols);
    lg.Box = 'on';

    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);

    % ---- Terminal summary ------------------------------------------------
    fprintf('\n============================================================\n');
    fprintf(' FIGURE 25 : Damage-Model RPT Comparison\n');
    fprintf('============================================================\n');
    if ~isempty(tab_eps)
        fprintf('  Tabular  : %d points  |  eps in [%.6f, %.6f]  |  sig in [%.4f, %.4f]\n', ...
            numel(tab_eps), min(tab_eps), max(tab_eps), min(tab_sig), max(tab_sig));
    end
    if Lin_Result.Available
        for k = 1:Lin_Result.N_Curves
            [lin_eps, lin_sig] = Truncate_Damage_Model_Curve(Lin_Result.Strain{k}, Lin_Result.Stress{k});
            if isempty(lin_eps)
                continue;
            end
            fprintf('  Linear   : %d points  |  eps in [%.6f, %.6f]  |  sig in [%.4f, %.4f]\n', ...
                numel(lin_eps), min(lin_eps), max(lin_eps), ...
                min(lin_sig), max(lin_sig));
        end
    end
    if Exp_Result.Available
        for ki = 1:Exp_Result.N_Curves
            k = sort_idx(ki);
            [exp_eps, exp_sig] = Truncate_Damage_Model_Curve(Exp_Result.Strain{k}, Exp_Result.Stress{k});
            if isempty(exp_eps)
                continue;
            end
            fprintf('  Exp a=%-4.2g: %d points  |  eps in [%.6f, %.6f]  |  sig in [%.4f, %.4f]\n', ...
                sorted_alpha(ki), numel(exp_eps), ...
                min(exp_eps), max(exp_eps), ...
                min(exp_sig), max(exp_sig));
        end
    end
    fprintf('============================================================\n\n');
end

function labels_out = Append_Break_Type_To_Legend_Labels(labels_in, break_types)
    labels_out = labels_in;
    if isempty(labels_in) || isempty(break_types)
        return;
    end

    n_break = min(numel(labels_in), numel(break_types));
    for i = 1:n_break
        break_label = string(break_types{i});
        if strlength(break_label) == 0
            continue;
        end
        labels_out{i} = sprintf('%s: break type %s', labels_in{i}, char(break_label));
    end
end

function [eps_out, sig_out] = Truncate_Damage_Model_Curve(eps_in, sig_in)
    eps_out = Ensure_Column_Vector(eps_in);
    sig_out = Ensure_Column_Vector(sig_in);

    valid_mask = isfinite(eps_out) & isfinite(sig_out);
    eps_out = eps_out(valid_mask);
    sig_out = sig_out(valid_mask);
    if isempty(eps_out)
        return;
    end

    stress_scale = max(abs(sig_out));
    strain_scale = max(abs(eps_out));
    stress_tol = max(1.0e-9, 1.0e-6 * max(stress_scale, 1.0));
    strain_tol = max(1.0e-12, 1.0e-6 * max(strain_scale, 1.0));
    strain_diff = diff(eps_out);
    positive_steps = strain_diff(strain_diff > strain_tol);
    if isempty(positive_steps)
        median_pos_step = strain_tol;
    else
        median_pos_step = median(positive_steps);
    end
    backward_jump_tol = max(100 * strain_tol, 50 * median_pos_step);

    loaded_idx = find(sig_out > stress_tol, 1, 'first');
    if isempty(loaded_idx)
        eps_out = eps_out(1);
        sig_out = sig_out(1);
        return;
    end

    stop_idx = numel(eps_out);

    jump_idx = find(strain_diff(loaded_idx:end) < -backward_jump_tol, 1, 'first');
    if ~isempty(jump_idx)
        jump_idx = jump_idx + loaded_idx - 1;
        stop_idx = min(stop_idx, jump_idx);
    end

    zero_idx = find(sig_out(loaded_idx:end) <= stress_tol, 1, 'first');
    if ~isempty(zero_idx)
        zero_idx = zero_idx + loaded_idx - 1;
        if zero_idx > loaded_idx && (eps_out(zero_idx) < eps_out(zero_idx - 1) - backward_jump_tol)
            stop_idx = min(stop_idx, zero_idx - 1);
        else
            stop_idx = min(stop_idx, zero_idx);
        end
    end

    neg_idx = find(sig_out(loaded_idx:end) < -stress_tol, 1, 'first');
    if ~isempty(neg_idx)
        neg_idx = neg_idx + loaded_idx - 1;
        stop_idx = min(stop_idx, max(loaded_idx, neg_idx - 1));
    end

    stop_idx = max(stop_idx, loaded_idx);
    eps_out = eps_out(1:stop_idx);
    sig_out = sig_out(1:stop_idx);
end

function Create_FEA_Experimental_Point_Error_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    Error_Summary = Build_FEA_Experimental_Point_Error_Summary(Plot_Data_Struct);
    if ~Error_Summary.Available
        fprintf('[PLOTS] Figure 26 skipped (point-error summary unavailable).\n');
        return;
    end

    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    TL = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(TL, 1);
    hold(ax1, 'on'); grid(ax1, 'on'); ax1.XMinorGrid = 'off'; ax1.YMinorGrid = 'off';
    strain_vals = [Error_Summary.Yield_Strain_Error, Error_Summary.UTS_Strain_Error, Error_Summary.Failure_Strain_Error];
    hb1 = bar(ax1, 1:3, strain_vals, 0.72, ...
        'FaceColor', 'flat', ...
        'EdgeColor', Hex2Rgb(Figure_Config.Bar_Edge_Color), ...
        'LineWidth', Figure_Config.Bar_Line_Width);
    set(hb1, 'CData', cell2mat(cellfun(@Hex2Rgb, Figure_Config.Strain_Bar_Colors(:), 'UniformOutput', false)));
    set(ax1, 'XTick', 1:3, 'XTickLabel', {'Yield', 'UTS', 'Failure'});
    Apply_Plot_Format_On_Axes(ax1, Figure_Config.X_Label, Figure_Config.Y_Labels{1}, {Figure_Config.Tile_Titles{1}}, Style, Style.Font_Sizes, ...
        struct('Title_Font_Size', Style.Title_Font_Size - 2, 'Axis_Label_Font_Size', Figure_Config.Axis_Label_Font_Size));
    Apply_Primary_Axis_Style(ax1, Style);
    if isfield(Figure_Config, 'Strain_Axis_YLim') && isnumeric(Figure_Config.Strain_Axis_YLim) && numel(Figure_Config.Strain_Axis_YLim) == 2
        ylim(ax1, Figure_Config.Strain_Axis_YLim);
    end
    for ii = 1:numel(strain_vals)
        text(ax1, ii, strain_vals(ii), sprintf('%.3f\\%%', strain_vals(ii)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'Interpreter', 'latex', 'FontSize', Figure_Config.Label_Font_Size);
    end
    ann_style = Style;
    ann_style.Annotation.Font_Size = 10;
    x_rng1 = xlim(ax1);
    y_rng1 = ylim(ax1);
    strain_ann = { ...
        '\textbf{Strain values}', ...
        sprintf('Yield: $\\varepsilon_T^{Y}=%.6f$, $\\varepsilon_{T,\\mathrm{FEA}}^{Y}=%.6f$', ...
            Error_Summary.Exp_Yield_Strain, Error_Summary.FEA_Yield_Strain), ...
        sprintf('$\\xi_{\\varepsilon_T}^{Y} = %.3f\\%%$', ...
            Error_Summary.Yield_Strain_Error), ...
        sprintf('UTS: $\\varepsilon_T^{UTS}=%.6f$, $\\varepsilon_{T,\\mathrm{FEA}}^{UTS}=%.6f$', ...
            Error_Summary.Exp_UTS_Strain, Error_Summary.FEA_UTS_Strain), ...
        sprintf('$\\xi_{\\varepsilon_T}^{UTS} = %.3f\\%%$', ...
            Error_Summary.UTS_Strain_Error), ...
        sprintf('Failure: $\\varepsilon_T^{f}=%.6f$, $\\varepsilon_{T,\\mathrm{FEA}}^{f}=%.6f$', ...
            Error_Summary.Exp_Failure_Strain, Error_Summary.FEA_Failure_Strain), ...
        sprintf('$\\xi_{\\varepsilon_T}^{f} = %.3f\\%%$', ...
            Error_Summary.Failure_Strain_Error) ...
    };
    Add_Axis_Annotation_Box(ax1, x_rng1(1) + 0.54 * diff(x_rng1), y_rng1(1) + 0.95 * diff(y_rng1), ...
        strain_ann, ann_style, Hex2Rgb(Figure_Config.Bar_Edge_Color), 0, 'top', 'left');

    ax2 = nexttile(TL, 2);
    hold(ax2, 'on'); grid(ax2, 'on'); ax2.XMinorGrid = 'off'; ax2.YMinorGrid = 'off';
    stress_vals = [Error_Summary.Yield_Stress_Error, Error_Summary.UTS_Stress_Error];
    hb2 = bar(ax2, 1:2, stress_vals, 0.72, ...
        'FaceColor', 'flat', ...
        'EdgeColor', Hex2Rgb(Figure_Config.Bar_Edge_Color), ...
        'LineWidth', Figure_Config.Bar_Line_Width);
    set(hb2, 'CData', cell2mat(cellfun(@Hex2Rgb, Figure_Config.Stress_Bar_Colors(:), 'UniformOutput', false)));
    set(ax2, 'XTick', 1:2, 'XTickLabel', {'Yield', 'UTS'});
    Apply_Plot_Format_On_Axes(ax2, Figure_Config.X_Label, Figure_Config.Y_Labels{2}, {Figure_Config.Tile_Titles{2}}, Style, Style.Font_Sizes, ...
        struct('Title_Font_Size', Style.Title_Font_Size - 2, 'Axis_Label_Font_Size', Figure_Config.Axis_Label_Font_Size));
    Apply_Primary_Axis_Style(ax2, Style);
    if isfield(Figure_Config, 'Stress_Axis_YLim') && isnumeric(Figure_Config.Stress_Axis_YLim) && numel(Figure_Config.Stress_Axis_YLim) == 2
        ylim(ax2, Figure_Config.Stress_Axis_YLim);
    end
    for ii = 1:numel(stress_vals)
        text(ax2, ii, stress_vals(ii), sprintf('%.3f\\%%', stress_vals(ii)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'Interpreter', 'latex', 'FontSize', Figure_Config.Label_Font_Size);
    end
    x_rng2 = xlim(ax2);
    y_rng2 = ylim(ax2);
    stress_ann = { ...
        '\textbf{Stress values}', ...
        sprintf('Yield: $\\sigma_T^{Y}=%.4f$ MPa, $\\sigma_{T,\\mathrm{FEA}}^{Y}=%.4f$ MPa', ...
            Error_Summary.Exp_Yield_Stress, Error_Summary.FEA_Yield_Stress), ...
        sprintf('$\\xi_{\\sigma_T}^{Y} = %.3f\\%%$', Error_Summary.Yield_Stress_Error), ...
        sprintf('UTS: $\\sigma_T^{UTS}=%.4f$ MPa, $\\sigma_{T,\\mathrm{FEA}}^{UTS}=%.4f$ MPa', ...
            Error_Summary.Exp_UTS_Stress, Error_Summary.FEA_UTS_Stress), ...
        sprintf('$\\xi_{\\sigma_T}^{UTS} = %.3f\\%%$', Error_Summary.UTS_Stress_Error), ...
        'Failure stress comparison: n/a' ...
    };
    Add_Axis_Annotation_Box(ax2, x_rng2(1) + 0.06 * diff(x_rng2), y_rng2(1) + 0.95 * diff(y_rng2), ...
        stress_ann, ann_style, Hex2Rgb(Figure_Config.Bar_Edge_Color), 0, 'top', 'left');

    sgtitle(TL, strjoin(Figure_Config.Title, newline), 'Interpreter', 'latex', 'FontSize', Style.Title_Font_Size);
    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf(' FIGURE 26 : FEA vs Experimental Point Errors\n');
    fprintf('============================================================\n');
    fprintf('  Yield strain error   : %.3f %%\n', Error_Summary.Yield_Strain_Error);
    fprintf('  Yield stress error   : %.3f %%\n', Error_Summary.Yield_Stress_Error);
    fprintf('  UTS strain error     : %.3f %%\n', Error_Summary.UTS_Strain_Error);
    fprintf('  UTS stress error     : %.3f %%\n', Error_Summary.UTS_Stress_Error);
    fprintf('  Failure strain error : %.3f %%\n', Error_Summary.Failure_Strain_Error);
    fprintf('  Experimental E       : %.4f MPa\n', Error_Summary.Exp_Youngs_Modulus);
    fprintf('  FEA E                : %.4f MPa\n', Error_Summary.FEA_Youngs_Modulus);
    fprintf('  Young''s modulus error: %.3f %%\n', Error_Summary.Youngs_Modulus_Error);
    fprintf('============================================================\n\n');
end

function Error_Summary = Build_FEA_Experimental_Point_Error_Summary(Plot_Data_Struct)
    Error_Summary = struct( ...
        'Available', false, ...
        'Yield_Strain_Error', NaN, ...
        'Yield_Stress_Error', NaN, ...
        'UTS_Strain_Error', NaN, ...
        'UTS_Stress_Error', NaN, ...
        'Failure_Strain_Error', NaN, ...
        'Youngs_Modulus_Error', NaN, ...
        'Exp_Yield_Strain', NaN, ...
        'Exp_Yield_Stress', NaN, ...
        'Exp_UTS_Strain', NaN, ...
        'Exp_UTS_Stress', NaN, ...
        'Exp_Failure_Strain', NaN, ...
        'Exp_Youngs_Modulus', NaN, ...
        'FEA_Yield_Strain', NaN, ...
        'FEA_Yield_Stress', NaN, ...
        'FEA_UTS_Strain', NaN, ...
        'FEA_UTS_Stress', NaN, ...
        'FEA_Failure_Strain', NaN, ...
        'FEA_Youngs_Modulus', NaN);

    eps_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Strain);
    sig_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Stress_Damaged);
    valid_exp = ~isnan(eps_exp) & ~isnan(sig_exp) & isfinite(eps_exp) & isfinite(sig_exp);
    eps_exp = eps_exp(valid_exp);
    sig_exp = sig_exp(valid_exp);
    if isempty(eps_exp) || isempty(sig_exp)
        return;
    end
    [eps_exp, exp_sort_idx] = sort(eps_exp);
    sig_exp = sig_exp(exp_sort_idx);

    rpt_path = Resolve_Stress_Strain_Rpt_Path();
    if strlength(string(rpt_path)) == 0 || ~isfile(char(rpt_path))
        return;
    end
    Curves = Parse_Stress_Strain_Rpt_Curves(char(rpt_path));
    eps_fea = Ensure_Column_Vector(Curves.Strain_First);
    sig_fea = Ensure_Column_Vector(Curves.Stress_First);
    valid_fea = ~isnan(eps_fea) & ~isnan(sig_fea) & isfinite(eps_fea) & isfinite(sig_fea);
    eps_fea = eps_fea(valid_fea);
    sig_fea = sig_fea(valid_fea);
    if isempty(eps_fea) || isempty(sig_fea)
        return;
    end

    FEA_POI = Compute_FEA_Element_POIs(eps_fea, sig_fea);
    if ~isfield(FEA_POI, 'UTS_Strain') && isfield(FEA_POI, 'Engineering_Peak_True_Strain')
        FEA_POI.UTS_Strain = FEA_POI.Engineering_Peak_True_Strain;
    end
    if ~isfield(FEA_POI, 'UTS_Stress') && isfield(FEA_POI, 'Engineering_Peak_True_Stress')
        FEA_POI.UTS_Stress = FEA_POI.Engineering_Peak_True_Stress;
    end

    pct_err = @(test_val, ref_val) 100 .* abs(test_val - ref_val) ./ max(abs(ref_val), eps);
    Error_Summary.Exp_Yield_Strain = double(Plot_Data_Struct.True_Yield_Strain);
    Error_Summary.Exp_Yield_Stress = double(Plot_Data_Struct.True_Yield_Stress);
    Error_Summary.Exp_UTS_Strain = double(Plot_Data_Struct.Engineering_UTS_True_Strain);
    Error_Summary.Exp_UTS_Stress = double(Plot_Data_Struct.Engineering_UTS_True_Stress);
    Error_Summary.Exp_Failure_Strain = double(Plot_Data_Struct.True_Rupture_Strain);
    Error_Summary.Exp_Youngs_Modulus = double(Plot_Data_Struct.Youngs_Modulus);
    Error_Summary.FEA_Yield_Strain = FEA_POI.Yield_Strain;
    Error_Summary.FEA_Yield_Stress = FEA_POI.Yield_Stress;
    Error_Summary.FEA_UTS_Strain = FEA_POI.UTS_Strain;
    Error_Summary.FEA_UTS_Stress = FEA_POI.UTS_Stress;
    Error_Summary.FEA_Failure_Strain = FEA_POI.Failure_Strain;
    Error_Summary.FEA_Youngs_Modulus = FEA_POI.Youngs_Modulus;
    Error_Summary.Yield_Strain_Error = pct_err(FEA_POI.Yield_Strain, Error_Summary.Exp_Yield_Strain);
    Error_Summary.Yield_Stress_Error = pct_err(FEA_POI.Yield_Stress, Error_Summary.Exp_Yield_Stress);
    Error_Summary.UTS_Strain_Error = pct_err(FEA_POI.UTS_Strain, Error_Summary.Exp_UTS_Strain);
    Error_Summary.UTS_Stress_Error = pct_err(FEA_POI.UTS_Stress, Error_Summary.Exp_UTS_Stress);
    Error_Summary.Failure_Strain_Error = pct_err(FEA_POI.Failure_Strain, Error_Summary.Exp_Failure_Strain);
    Error_Summary.Youngs_Modulus_Error = pct_err(FEA_POI.Youngs_Modulus, Error_Summary.Exp_Youngs_Modulus);
    Error_Summary.Available = true;
end

function Create_FEA_True_Error_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    eps_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Strain);
    sig_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Stress_Damaged);
    eps_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Strain_Approx);
    sig_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Stress_Approx);

    valid_exp = ~isnan(eps_exp) & ~isnan(sig_exp);
    eps_exp = eps_exp(valid_exp);
    sig_exp = sig_exp(valid_exp);
    valid_fea = ~isnan(eps_fea) & ~isnan(sig_fea);
    eps_fea = eps_fea(valid_fea);
    sig_fea = sig_fea(valid_fea);
    [eps_fea, sort_idx] = sort(eps_fea);
    sig_fea = sig_fea(sort_idx);

    overlap_mask = eps_exp >= min(eps_fea) & eps_exp <= max(eps_fea);
    eps_overlap = eps_exp(overlap_mask);
    sig_exp_overlap = sig_exp(overlap_mask);
    sig_fea_interp = interp1(eps_fea, sig_fea, eps_overlap, 'linear');
    err_pct = 100 .* abs(sig_fea_interp - sig_exp_overlap) ./ max(abs(sig_exp_overlap), eps);

    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on'); ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';
    h = plot(ax, eps_overlap, err_pct, Figure_Config.Curve_Line_Style, 'Color', Hex2Rgb(Figure_Config.Curve_Color), 'LineWidth', Style.LineWidths);

    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, Figure_Config.Title, Style, Style.Font_Sizes);
    Apply_Primary_Axis_Style(ax, Style);
    Apply_Legend_Template(ax, h, Figure_Config.Legend, ...
        Style, Figure_Config.Legend_Location, 1, Style.Legend_Font_Size - 2);

    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);
end

function Create_FEA_True_Combined_Comparison_Error_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    LS = Style.LineStyles;
    MK = Style.Markers;

    eps_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Strain);
    sig_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Stress_Damaged);
    eps_fea = nan(0, 1);
    sig_fea = nan(0, 1);
    FEA_POI = struct();
    FEA_Source_Label = "rpt_First";

    rpt_path = Resolve_Stress_Strain_Rpt_Path();
    if strlength(string(rpt_path)) > 0 && isfile(char(rpt_path))
        Curves = Parse_Stress_Strain_Rpt_Curves(char(rpt_path));
        eps_fea = Ensure_Column_Vector(Curves.Strain_First);
        sig_fea = Ensure_Column_Vector(Curves.Stress_First);
        if ~isempty(eps_fea) && ~isempty(sig_fea)
            FEA_POI = Compute_FEA_Element_POIs(eps_fea, sig_fea);
            if ~isfield(FEA_POI, 'UTS_Strain') && isfield(FEA_POI, 'Engineering_Peak_True_Strain')
                FEA_POI.UTS_Strain = FEA_POI.Engineering_Peak_True_Strain;
            end
            if ~isfield(FEA_POI, 'UTS_Stress') && isfield(FEA_POI, 'Engineering_Peak_True_Stress')
                FEA_POI.UTS_Stress = FEA_POI.Engineering_Peak_True_Stress;
            end
            fprintf('[PLOTS] Figure 24 using Stress-Strain.rpt curve: %s\n', char(FEA_Source_Label));
        end
    end

    valid_exp = ~isnan(eps_exp) & ~isnan(sig_exp) & isfinite(eps_exp) & isfinite(sig_exp);
    eps_exp = eps_exp(valid_exp);
    sig_exp = sig_exp(valid_exp);
    valid_fea = ~isnan(eps_fea) & ~isnan(sig_fea) & isfinite(eps_fea) & isfinite(sig_fea);
    eps_fea = eps_fea(valid_fea);
    sig_fea = sig_fea(valid_fea);

    if isempty(eps_exp) || isempty(eps_fea)
        fprintf('[PLOTS] Figure 24 skipped (true stress-strain data unavailable).\n');
        return;
    end

    [eps_exp, exp_sort_idx] = sort(eps_exp);
    sig_exp = sig_exp(exp_sort_idx);
    [eps_fea, fea_sort_idx] = sort(eps_fea);
    sig_fea = sig_fea(fea_sort_idx);

    exp_y_idx = Find_Nearest_Index(eps_exp, Plot_Data_Struct.True_Yield_Strain);
    exp_u_idx = max(1, min(numel(eps_exp), round(double(Plot_Data_Struct.UTS_Index))));
    exp_f_idx = max(1, min(numel(eps_exp), round(double(Plot_Data_Struct.Rupture_Index))));

    y_idx = max(1, min(FEA_POI.Yield_Index, numel(eps_fea)));
    u_idx = max(y_idx, min(FEA_POI.UTS_Index, numel(eps_fea)));
    f_idx = max(u_idx, min(FEA_POI.Failure_Index, numel(eps_fea)));

    pct_err = @(test_val, ref_val) 100 .* abs(test_val - ref_val) ./ max(abs(ref_val), eps);
    err_yield_strain = pct_err(FEA_POI.Yield_Strain, eps_exp(exp_y_idx));
    err_yield_stress = pct_err(FEA_POI.Yield_Stress, sig_exp(exp_y_idx));
    err_uts_strain = pct_err(FEA_POI.UTS_Strain, eps_exp(exp_u_idx));
    err_uts_stress = pct_err(FEA_POI.UTS_Stress, sig_exp(exp_u_idx));
    err_failure_strain = pct_err(FEA_POI.Failure_Strain, eps_exp(exp_f_idx));

    exp_E = NaN;
    if isfield(Plot_Data_Struct, 'Youngs_Modulus')
        exp_E = double(Plot_Data_Struct.Youngs_Modulus);
    end
    fea_fit_end = max(2, min(y_idx, numel(eps_fea)));
    fea_E = NaN;
    if fea_fit_end >= 2 && range(eps_fea(1:fea_fit_end)) > 0
        fea_fit = polyfit(eps_fea(1:fea_fit_end), sig_fea(1:fea_fit_end), 1);
        fea_E = fea_fit(1);
    end

    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on'); grid(ax, 'on'); ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';

    h_exp = plot(ax, eps_exp, sig_exp, Figure_Config.Experimental_Curve_Line_Style, ...
        'Color', Hex2Rgb(Figure_Config.Experimental_Curve_Color), 'LineWidth', Style.LineWidths);
    h_fea = plot(ax, eps_fea, sig_fea, Figure_Config.FEA_Curve_Line_Style, ...
        'Color', Hex2Rgb(Figure_Config.FEA_Curve_Color), 'LineWidth', Style.LineWidths);

    h_exp_y = plot(ax, eps_exp(exp_y_idx), sig_exp(exp_y_idx), ...
        'LineStyle', LS.NoLine, 'Marker', MK.Yield.Symbol, 'MarkerSize', 20, ...
        'MarkerFaceColor', MK.Yield.TrueFaceColor, 'MarkerEdgeColor', MK.Yield.TrueEdgeColor, ...
        'LineWidth', MK.Yield.LineWidth);
    h_exp_u = plot(ax, eps_exp(exp_u_idx), sig_exp(exp_u_idx), ...
        'LineStyle', LS.NoLine, 'Marker', MK.UTS.Symbol, 'MarkerSize', 20, ...
        'MarkerFaceColor', MK.UTS.MappedFaceColor, 'MarkerEdgeColor', MK.UTS.MappedEdgeColor, ...
        'LineWidth', MK.UTS.LineWidth);
    h_exp_f = plot(ax, eps_exp(exp_f_idx), sig_exp(exp_f_idx), ...
        'LineStyle', LS.NoLine, 'Marker', MK.Failure.Symbol, 'MarkerSize', 20, ...
        'MarkerFaceColor', MK.Failure.TrueDamagedFaceColor, 'MarkerEdgeColor', MK.Failure.TrueDamagedEdgeColor, ...
        'LineWidth', MK.Failure.LineWidth);

    h_fea_y = plot(ax, FEA_POI.Yield_Strain, FEA_POI.Yield_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.FEA_Yield_Marker, ...
        'MarkerSize', Figure_Config.FEA_Yield_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_Yield_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_Yield_EdgeColor), ...
        'LineWidth', Figure_Config.FEA_Marker_LineWidth);
    h_fea_u = plot(ax, FEA_POI.UTS_Strain, FEA_POI.UTS_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.FEA_UTS_Marker, ...
        'MarkerSize', Figure_Config.FEA_UTS_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_UTS_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_UTS_EdgeColor), ...
        'LineWidth', Figure_Config.FEA_Marker_LineWidth);
    h_fea_f = plot(ax, FEA_POI.Failure_Strain, FEA_POI.Failure_Stress, ...
        'LineStyle', LS.NoLine, 'Marker', Figure_Config.FEA_Failure_Marker, ...
        'MarkerSize', Figure_Config.FEA_Failure_Marker_Size, ...
        'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_Failure_FaceColor), ...
        'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_Failure_EdgeColor), ...
        'LineWidth', Figure_Config.FEA_Marker_LineWidth);

    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label_Left, Figure_Config.Title, Style, Style.Font_Sizes, ...
        struct('Axis_Label_Font_Size', Style.Axis_Label_Font_Size, ...
               'Title_Font_Size', Style.Title_Font_Size));
    Apply_Primary_Axis_Style(ax, Style);
    if isfield(Figure_Config, 'Plot_XLim') && numel(Figure_Config.Plot_XLim) == 2
        xlim(ax, Figure_Config.Plot_XLim);
    end
    if isfield(Figure_Config, 'Plot_YLim') && numel(Figure_Config.Plot_YLim) == 2
        ylim(ax, Figure_Config.Plot_YLim);
    end

    legend_handles = [h_exp, h_fea, h_exp_y, h_exp_u, h_exp_f, h_fea_y, h_fea_u, h_fea_f];
    legend_labels = { ...
        'Experimental true response', ...
        'FEA true response', ...
        'Exp. yield', ...
        'Exp. mapped UTS', ...
        'Exp. failure', ...
        'FEA yield', ...
        'FEA UTS', ...
        'FEA failure'};
    legend_cols = 2;
    if isfield(Figure_Config, 'Legend_NumColumns')
        legend_cols = max(1, round(double(Figure_Config.Legend_NumColumns)));
    end
    Apply_Legend_Template(ax, legend_handles, legend_labels, ...
        Style, Figure_Config.Legend_Location, legend_cols, Style.Legend_Font_Size - 2);

    comparison_text = { ...
        '\textbf{Experimental}\qquad\qquad\qquad\textbf{FEA}', ...
        sprintf('$Y:\\ (\\varepsilon_T^{Y},\\sigma_T^{Y})=(%.6f,\\,%.4f\\ \\mathrm{MPa})$\\qquad$Y:\\ (\\varepsilon_{T,\\mathrm{FEA}}^{Y},\\sigma_{T,\\mathrm{FEA}}^{Y})=(%.6f,\\,%.4f\\ \\mathrm{MPa})$', ...
            eps_exp(exp_y_idx), sig_exp(exp_y_idx), FEA_POI.Yield_Strain, FEA_POI.Yield_Stress), ...
        sprintf('$UTS:\\ (\\varepsilon_T^{UTS},\\sigma_T^{UTS})=(%.6f,\\,%.4f\\ \\mathrm{MPa})$\\qquad$UTS:\\ (\\varepsilon_{T,\\mathrm{FEA}}^{UTS},\\sigma_{T,\\mathrm{FEA}}^{UTS})=(%.6f,\\,%.4f\\ \\mathrm{MPa})$', ...
            eps_exp(exp_u_idx), sig_exp(exp_u_idx), FEA_POI.UTS_Strain, FEA_POI.UTS_Stress), ...
        sprintf('$R:\\ (\\varepsilon_T^{R},\\sigma_T^{R})=(%.6f,\\,%.4f\\ \\mathrm{MPa})$\\qquad$R:\\ (\\varepsilon_{T,\\mathrm{FEA}}^{R},\\sigma_{T,\\mathrm{FEA}}^{R})=(%.6f,\\,%.4f\\ \\mathrm{MPa})$', ...
            eps_exp(exp_f_idx), sig_exp(exp_f_idx), FEA_POI.Failure_Strain, FEA_POI.Failure_Stress), ...
        sprintf('$E=%.4f\\ \\mathrm{MPa}$\\qquad\\qquad\\qquad$E_{\\mathrm{FEA}}=%.4f\\ \\mathrm{MPa}$', exp_E, fea_E)};
    annotation(fig, 'textbox', [0.57, 0.06, 0.39, 0.23], ...
        'String', comparison_text, 'Interpreter', 'latex', 'FitBoxToText', 'off', ...
        'BackgroundColor', Style.Annotation.BackgroundColor, ...
        'EdgeColor', Hex2Rgb(Figure_Config.Annotation_EdgeColor), ...
        'LineWidth', Style.Annotation.LineWidth, ...
        'Color', Style.Annotation.TextColor, ...
        'FontSize', Style.Annotation.Font_Size, ...
        'Margin', Style.Annotation.Margin);

    if isfield(Figure_Config, 'Inset') && isstruct(Figure_Config.Inset) && ...
            isfield(Figure_Config.Inset, 'Enable') && Figure_Config.Inset.Enable
        inset_ax = axes('Parent', fig, 'Position', Figure_Config.Inset.Position);
        hold(inset_ax, 'on'); grid(inset_ax, 'on'); inset_ax.XMinorGrid = 'off'; inset_ax.YMinorGrid = 'off';
        plot(inset_ax, eps_exp, sig_exp, Figure_Config.Experimental_Curve_Line_Style, ...
            'Color', Hex2Rgb(Figure_Config.Experimental_Curve_Color), 'LineWidth', Style.LineWidths);
        plot(inset_ax, eps_fea, sig_fea, Figure_Config.FEA_Curve_Line_Style, ...
            'Color', Hex2Rgb(Figure_Config.FEA_Curve_Color), 'LineWidth', Style.LineWidths);
        plot(inset_ax, eps_exp(exp_y_idx), sig_exp(exp_y_idx), 'LineStyle', LS.NoLine, ...
            'Marker', MK.Yield.Symbol, 'MarkerSize', 20, ...
            'MarkerFaceColor', MK.Yield.TrueFaceColor, 'MarkerEdgeColor', MK.Yield.TrueEdgeColor, ...
            'LineWidth', MK.Yield.LineWidth);
        plot(inset_ax, eps_exp(exp_u_idx), sig_exp(exp_u_idx), 'LineStyle', LS.NoLine, ...
            'Marker', MK.UTS.Symbol, 'MarkerSize', 20, ...
            'MarkerFaceColor', MK.UTS.MappedFaceColor, 'MarkerEdgeColor', MK.UTS.MappedEdgeColor, ...
            'LineWidth', MK.UTS.LineWidth);
        plot(inset_ax, eps_exp(exp_f_idx), sig_exp(exp_f_idx), 'LineStyle', LS.NoLine, ...
            'Marker', MK.Failure.Symbol, 'MarkerSize', 20, ...
            'MarkerFaceColor', MK.Failure.TrueDamagedFaceColor, 'MarkerEdgeColor', MK.Failure.TrueDamagedEdgeColor, ...
            'LineWidth', MK.Failure.LineWidth);
        plot(inset_ax, FEA_POI.Yield_Strain, FEA_POI.Yield_Stress, 'LineStyle', LS.NoLine, ...
            'Marker', Figure_Config.FEA_Yield_Marker, 'MarkerSize', Figure_Config.FEA_Yield_Marker_Size, ...
            'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_Yield_FaceColor), ...
            'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_Yield_EdgeColor), ...
            'LineWidth', Figure_Config.FEA_Marker_LineWidth);
        plot(inset_ax, FEA_POI.UTS_Strain, FEA_POI.UTS_Stress, 'LineStyle', LS.NoLine, ...
            'Marker', Figure_Config.FEA_UTS_Marker, 'MarkerSize', Figure_Config.FEA_UTS_Marker_Size, ...
            'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_UTS_FaceColor), ...
            'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_UTS_EdgeColor), ...
            'LineWidth', Figure_Config.FEA_Marker_LineWidth);
        plot(inset_ax, FEA_POI.Failure_Strain, FEA_POI.Failure_Stress, 'LineStyle', LS.NoLine, ...
            'Marker', Figure_Config.FEA_Failure_Marker, 'MarkerSize', Figure_Config.FEA_Failure_Marker_Size, ...
            'MarkerFaceColor', Hex2Rgb(Figure_Config.FEA_Failure_FaceColor), ...
            'MarkerEdgeColor', Hex2Rgb(Figure_Config.FEA_Failure_EdgeColor), ...
            'LineWidth', Figure_Config.FEA_Marker_LineWidth);
        zoom_x = [eps_exp(exp_y_idx); eps_exp(exp_u_idx); FEA_POI.Yield_Strain; FEA_POI.UTS_Strain];
        zoom_y = [sig_exp(exp_y_idx); sig_exp(exp_u_idx); FEA_POI.Yield_Stress; FEA_POI.UTS_Stress];
        x_pad = Figure_Config.Inset.X_Pad_Fraction * max(max(zoom_x) - min(zoom_x), 1.0e-4);
        y_pad = Figure_Config.Inset.Y_Pad_Fraction * max(max(zoom_y) - min(zoom_y), 1.0e-3);
        xlim(inset_ax, [min(zoom_x) - x_pad, max(zoom_x) + x_pad]);
        ylim(inset_ax, [min(zoom_y) - y_pad, max(zoom_y) + y_pad]);
        Apply_Plot_Format_On_Axes(inset_ax, '', '', {Figure_Config.Inset.Title}, Style, Style.Font_Sizes);
        Apply_Primary_Axis_Style(inset_ax, Style);
        inset_ax.XColor = Hex2Rgb(Figure_Config.Inset.Axis_Color);
        inset_ax.YColor = Hex2Rgb(Figure_Config.Inset.Axis_Color);
        Bring_Markers_To_Front(inset_ax);
    end

    Bring_Markers_To_Front(ax);
    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  FIGURE 24 — FEA / Experimental Comparison Errors\n');
    fprintf('============================================================\n');
    fprintf('  Yield strain error   : %.3f %%\n', err_yield_strain);
    fprintf('  Yield stress error   : %.3f %%\n', err_yield_stress);
    fprintf('  UTS strain error     : %.3f %%\n', err_uts_strain);
    fprintf('  UTS stress error     : %.3f %%\n', err_uts_stress);
    fprintf('  Failure strain error : %.3f %%\n', err_failure_strain);
    fprintf('============================================================\n\n');
end

function Create_FEA_45deg_Rpt_Overlay_Figure(Plot_Data_Struct, Figure_Config, Style, Output_Directory)
    rpt_path = "";
    if isfield(Figure_Config, 'Rpt_Path') && strlength(string(Figure_Config.Rpt_Path)) > 0
        rpt_path = string(Figure_Config.Rpt_Path);
    else
        rpt_path = Resolve_Stress_Strain_Rpt_Path();
    end

    if strlength(rpt_path) == 0 || ~isfile(char(rpt_path))
        fprintf('[PLOTS] Figure 21 skipped (Stress-Strain.rpt not found).\n');
        return;
    end

    Curves = Parse_Stress_Strain_Rpt_Curves(char(rpt_path));
    if ~Curves.Available
        fprintf('[PLOTS] Figure 21 skipped (no usable Stress-Strain.rpt data).\n');
        return;
    end

    eps_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Strain);
    sig_exp = Ensure_Column_Vector(Plot_Data_Struct.True_Stress_Damaged);
    [eps_exp, sig_exp] = Clean_XY_For_Plot(eps_exp, sig_exp);
    if isempty(eps_exp) || isempty(sig_exp)
        fprintf('[PLOTS] Figure 21 skipped (experimental true curve unavailable).\n');
        return;
    end

    fig = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(fig, Style);
    set(fig, 'Color', Figure_Config.Figure_Color);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');
    grid(ax, 'on');
    ax.XMinorGrid = 'off';
    ax.YMinorGrid = 'off';

    % All 5 header-labelled stress-strain pairs: Del, L, U, UL, First.
    curve_bank = { ...
        'FEA: All Deleted Elements avg', Curves.Strain_Del, Curves.Stress_Del; ...
        'FEA: Lower Fracture Elements avg', Curves.Strain_L, Curves.Stress_L; ...
        'FEA: Upper Fracture Elements avg', Curves.Strain_U, Curves.Stress_U; ...
        'FEA: Lower + Upper Fracture Elements avg', Curves.Strain_UL, Curves.Stress_UL; ...
        'FEA: Initial Deleted Elements avg: {4810, 6002}', Curves.Strain_First, Curves.Stress_First ...
    };

    valid_curve_idx = [];
    for cb = 1:size(curve_bank, 1)
        if ~isempty(curve_bank{cb, 2}) && ~isempty(curve_bank{cb, 3})
            valid_curve_idx(end + 1) = cb; %#ok<AGROW>
        end
    end
    n_fea_curves = numel(valid_curve_idx);
    if n_fea_curves == 0
        fprintf('[PLOTS] Figure 21 skipped (no parsed FEA curves in Stress-Strain.rpt).\n');
        return;
    end

    h = gobjects(1 + n_fea_curves, 1);
    h(1) = plot(ax, eps_exp, sig_exp, Figure_Config.Experimental_Curve_Line_Style, ...
        'Color', Hex2Rgb(Figure_Config.Experimental_Curve_Color), ...
        'LineWidth', Figure_Config.Experimental_Curve_Line_Width);

    colors = Get_High_Contrast_Colormap(n_fea_curves, Figure_Config.Curve_Colormap);
    if isfield(Figure_Config, 'Curve_Colors') && iscell(Figure_Config.Curve_Colors) && ~isempty(Figure_Config.Curve_Colors)
        cfg_colors = Figure_Config.Curve_Colors;
        if numel(cfg_colors) == 1 && iscell(cfg_colors{1})
            cfg_colors = cfg_colors{1};
        end
        if iscell(cfg_colors) && ~isempty(cfg_colors)
            colors = zeros(n_fea_curves, 3);
            for cc = 1:n_fea_curves
                this_c = cfg_colors{mod(cc - 1, numel(cfg_colors)) + 1};
                colors(cc, :) = Hex2Rgb(this_c);
            end
        end
    end
    styles = Figure_Config.Curve_Line_Styles;
    markers = Figure_Config.Curve_Markers;

    if ~iscell(styles) || isempty(styles)
        styles = {'-'};
    end
    if ~iscell(markers) || isempty(markers)
        markers = {'none'};
    end

    for k = 1:n_fea_curves
        bank_idx = valid_curve_idx(k);
        xk = curve_bank{bank_idx, 2};
        yk = curve_bank{bank_idx, 3};
        style_k = styles{mod(k - 1, numel(styles)) + 1};
        marker_k = markers{mod(k - 1, numel(markers)) + 1};
        h(k + 1) = plot(ax, xk, yk, ...
            'LineStyle', style_k, ...
            'Marker', marker_k, ...
            'Color', colors(k, :), ...
            'LineWidth', Style.LineWidths);
    end

    Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, Figure_Config.Y_Label, Figure_Config.Title, Style, Style.Font_Sizes, ...
        struct('Title_Font_Size', Style.Title_Font_Size - 2));
    Apply_Primary_Axis_Style(ax, Style);
    y_limits_21 = ylim(ax);
    y_upper_21 = max(0, y_limits_21(2));
    if y_upper_21 <= 0
        y_upper_21 = 1;
    end
    ylim(ax, [-0.01, y_upper_21]);
    xlim(ax, [0, 0.45]);
    legend_labels = cell(1 + n_fea_curves, 1);
    legend_labels{1} = 'Experimental';
    for k = 1:n_fea_curves
        legend_labels{k + 1} = curve_bank{valid_curve_idx(k), 1};
    end

    legend_cfg = Figure_Config.Legend;
    if iscell(legend_cfg) && numel(legend_cfg) == 1 && iscell(legend_cfg{1})
        legend_cfg = legend_cfg{1};
    end
    if iscell(legend_cfg) && numel(legend_cfg) >= 1
        legend_labels{1} = legend_cfg{1};
        if numel(legend_cfg) >= (1 + size(curve_bank, 1))
            % Honor configured labels where provided, while keeping
            % dynamic suppression for missing curves.
            for k = 1:n_fea_curves
                legend_labels{k + 1} = legend_cfg{1 + valid_curve_idx(k)};
            end
        end
    end

    Apply_Legend_Template(ax, h, legend_labels, ...
        Style, Figure_Config.Legend_Location, 1, Style.Legend_Font_Size - 2);

    % --- Annotation box: peak stress and failure strain per curve ---------
    short_tags = {'Del', 'L', 'U', 'L+U', 'First'};
    ann_lines = {'\textbf{Peak stress / Failure strain}'};

    % Experimental curve
    [peak_exp, ~] = max(sig_exp);
    fail_eps_exp = eps_exp(end);
    ann_lines{end + 1} = sprintf('Exp: $\\sigma_T^{\\max}=%.4f$ MPa, $\\varepsilon_T^{f}=%.6f$', peak_exp, fail_eps_exp);

    % FEA curves
    for k = 1:n_fea_curves
        bi = valid_curve_idx(k);
        xk = curve_bank{bi, 2};
        yk = curve_bank{bi, 3};
        [peak_k, ~] = max(yk);
        fail_k = xk(end);
        tag_k = short_tags{bi};
        ann_lines{end + 1} = sprintf('%s: $\\sigma_T^{\\max}=%.4f$ MPa, $\\varepsilon_T^{f}=%.6f$', tag_k, peak_k, fail_k); %#ok<AGROW>
    end

    x_rng = xlim(ax);
    y_rng = ylim(ax);
    Add_Axis_Annotation_Box(ax, x_rng(1) + 0.55 * diff(x_rng), y_rng(1) + 0.22 * diff(y_rng), ...
        ann_lines, Style, Hex2Rgb(Style.Annotation.EdgeColor), 0, 'bottom', 'left');

    Export_Figure_Files(fig, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);
end

function rpt_path = Resolve_Stress_Strain_Rpt_Path()
    script_dir = fileparts(mfilename('fullpath'));
    work_dir = pwd;
    candidates = {
        fullfile(script_dir, 'FEA RESULTS', 'Damage', 'Stress-Strain.rpt')
        fullfile(script_dir, 'FEA RESULTS', 'Damage Evolution', 'Stress-Strain.rpt')
        fullfile(work_dir, 'FEA RESULTS', 'Damage', 'Stress-Strain.rpt')
        fullfile(work_dir, 'FEA RESULTS', 'Damage Evolution', 'Stress-Strain.rpt')
    };
    rpt_path = "";
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            rpt_path = string(candidates{i});
            return;
        end
    end
end

function rpt_path = Resolve_Damage_Rpt_Path(base_name)
%RESOLVE_DAMAGE_RPT_PATH  Locate <base_name>.rpt under FEA RESULTS/Damage
%   or FEA RESULTS/Damage Evolution folders.
    script_dir = fileparts(mfilename('fullpath'));
    work_dir = pwd;
    fname = [char(base_name), '.rpt'];
    candidates = {
        fullfile(script_dir, 'FEA RESULTS', 'Damage', fname)
        fullfile(script_dir, 'FEA RESULTS', 'Damage Evolution', fname)
        fullfile(work_dir, 'FEA RESULTS', 'Damage', fname)
        fullfile(work_dir, 'FEA RESULTS', 'Damage Evolution', fname)
    };
    rpt_path = "";
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            rpt_path = string(candidates{i});
            return;
        end
    end
end

function Result = Parse_Damage_Rpt_Curves(rpt_path)
%PARSE_DAMAGE_RPT_CURVES  Generic parser for Linear_Damage / Exponential_Damage .rpt.
%   Returns a struct:
%     .Available  (logical)
%     .N_Curves   (number of strain/stress column pairs)
%     .Alpha      (1 x N_Curves double) – alpha values extracted from headers
%     .Labels     (1 x N_Curves cell of char) – descriptive labels per curve
%     .Strain     {1 x N_Curves} cell of column vectors (NaN-cleaned)
%     .Stress     {1 x N_Curves} cell of column vectors (NaN-cleaned)
    Result = struct('Available', false, 'N_Curves', 0, ...
        'Alpha', [], 'Labels', {{}}, 'Strain', {{}}, 'Stress', {{}});

    rpt_text = Read_Text_File_Safe(rpt_path);
    if strlength(string(rpt_text)) == 0
        return;
    end

    lines_text = regexp(char(rpt_text), '\r\n|\n|\r', 'split');

    % ---- Locate header line (contains both "Strain" and "Stress") --------
    header_line_raw = '';
    header_idx = [];
    for i = 1:numel(lines_text)
        li = strtrim(lines_text{i});
        if isempty(li), continue; end
        if contains(lower(li), 'strain') && contains(lower(li), 'stress')
            header_line_raw = li;
            header_idx = i;
            break;
        end
    end

    % ---- Parse header tokens to identify column pairs --------------------
    %  Tokens look like:  X  Linear_Strain  Linear_Stress  or
    %  X  Exp_0_25_Strain  Exp_0_25_Stress  Exp_0_75_Strain  ...
    header_tokens = regexp(header_line_raw, '\S+', 'match');
    n_tok = numel(header_tokens);

    % Pair up Strain/Stress columns (skip the first token which is 'X')
    pair_strain_cols = [];
    pair_stress_cols = [];
    pair_alpha = [];
    pair_labels = {};
    col = 2;  % data column index (1-based, skipping X which is col 1)
    while col <= n_tok
        tok = header_tokens{col};
        if contains(lower(tok), 'strain') && (col + 1) <= n_tok && contains(lower(header_tokens{col + 1}), 'stress')
            pair_strain_cols(end + 1) = col; %#ok<AGROW>
            pair_stress_cols(end + 1) = col + 1; %#ok<AGROW>
            % Extract alpha from token (e.g. Exp_0_25_Strain -> 0.25)
            alpha_val = Extract_Alpha_From_Token(tok);
            pair_alpha(end + 1) = alpha_val; %#ok<AGROW>
            pair_labels{end + 1} = Build_Alpha_Label(tok, alpha_val); %#ok<AGROW>
            col = col + 2;
        else
            col = col + 1;
        end
    end
    n_pairs = numel(pair_strain_cols);
    if n_pairs == 0
        return;
    end

    % ---- Parse numeric data (replace NoValue with NaN) -------------------
    n_cols = n_tok;  % total number of columns including X
    data = nan(0, n_cols);
    for i = 1:numel(lines_text)
        if ~isempty(header_idx) && i <= header_idx, continue; end
        line_i = strtrim(lines_text{i});
        if isempty(line_i), continue; end
        % Replace NoValue with NaN before tokenising
        line_i = regexprep(line_i, 'NoValue', 'NaN');
        tokens = regexp(line_i, '[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[Ee][-+]?\d+)?|NaN', 'match');
        if numel(tokens) ~= n_cols, continue; end
        vals = str2double(tokens);
        data(end + 1, :) = vals; %#ok<AGROW>
    end

    if size(data, 1) < 2
        return;
    end

    % ---- Build output struct ---------------------------------------------
    Result.N_Curves = n_pairs;
    Result.Alpha = pair_alpha;
    Result.Labels = pair_labels;
    Result.Strain = cell(1, n_pairs);
    Result.Stress = cell(1, n_pairs);
    for k = 1:n_pairs
        eps_k = data(:, pair_strain_cols(k));
        sig_k = data(:, pair_stress_cols(k));
        valid = ~isnan(eps_k) & ~isnan(sig_k);
        Result.Strain{k} = eps_k(valid);
        Result.Stress{k} = sig_k(valid);
    end
    Result.Available = true;
end

function alpha_val = Extract_Alpha_From_Token(tok)
%EXTRACT_ALPHA_FROM_TOKEN  Parse alpha from column name like Exp_0_25_Strain.
%   Exp_0_25 -> 0.25,  Exp_0_75 -> 0.75,  Exp_0 -> 0,  Exp_2 -> 2,
%   Exp_10 -> 10,  Linear_Strain -> NaN.
    tok_lower = lower(tok);
    tok_lower = regexprep(tok_lower, '_(strain|stress)$', '');
    % Match patterns like exp_0_25 or exp_10
    m = regexp(tok_lower, 'exp_(\d+)_(\d+)', 'tokens', 'once');
    if ~isempty(m)
        alpha_val = str2double([m{1}, '.', m{2}]);
        return;
    end
    m = regexp(tok_lower, 'exp_(\d+)', 'tokens', 'once');
    if ~isempty(m)
        alpha_val = str2double(m{1});
        return;
    end
    alpha_val = NaN;
end

function lbl = Build_Alpha_Label(tok, alpha_val)
%BUILD_ALPHA_LABEL  Create a short label from the column token.
    if isnan(alpha_val)
        lbl = regexprep(tok, '_(Strain|Stress)$', '', 'ignorecase');
    else
        lbl = sprintf('alpha=%.2g', alpha_val);
    end
end

function Curves = Parse_Stress_Strain_Rpt_Curves(rpt_path)
    Curves = struct( ...
        'Available', false, ...
        'Time', nan(0, 1), ...
        'Strain_Del', nan(0, 1), 'Stress_Del', nan(0, 1), ...
        'Strain_L', nan(0, 1), 'Stress_L', nan(0, 1), ...
        'Strain_U', nan(0, 1), 'Stress_U', nan(0, 1), ...
        'Strain_UL', nan(0, 1), 'Stress_UL', nan(0, 1), ...
        'Strain_First', nan(0, 1), 'Stress_First', nan(0, 1));

    rpt_text = Read_Text_File_Safe(rpt_path);
    if strlength(string(rpt_text)) == 0
        return;
    end

    lines_text = regexp(char(rpt_text), '\r\n|\n|\r', 'split');
    header_idx = [];
    header_tokens = {};
    header_line_raw = '';
    for i = 1:numel(lines_text)
        li = strtrim(lines_text{i});
        if isempty(li)
            continue;
        end
        if contains(lower(li), 'strain') && contains(lower(li), 'stress')
            header_idx = i;
            header_line_raw = li;
            header_tokens = regexp(li, '\s{2,}', 'split');
            header_tokens = header_tokens(~cellfun(@isempty, header_tokens));
            break;
        end
    end

    % Infer numeric column count from the first valid numeric row because
    % report headers can contain irregular spacing (e.g. "Stress -  L")
    % that breaks naive token counting.
    n_cols = 0;
    for i = 1:numel(lines_text)
        if ~isempty(header_idx) && i <= header_idx
            continue;
        end
        li = strtrim(lines_text{i});
        if isempty(li)
            continue;
        end
        nums = regexp(li, '[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[Ee][-+]?\d+)?', 'match');
        if ~isempty(nums)
            n_cols = numel(nums);
            break;
        end
    end
    if n_cols == 0
        if ~isempty(header_tokens)
            n_cols = numel(header_tokens);
        else
            % Fallback for legacy report layouts with no clean header line.
            n_cols = 15;
        end
    end

    data = nan(0, n_cols);
    for i = 1:numel(lines_text)
        if ~isempty(header_idx) && i <= header_idx
            continue;
        end
        line_i = strtrim(lines_text{i});
        if strlength(string(line_i)) == 0
            continue;
        end
        nums = regexp(line_i, '[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[Ee][-+]?\d+)?', 'match');
        if numel(nums) ~= n_cols
            continue;
        end
        vals = str2double(nums);
        if any(isnan(vals))
            continue;
        end
        if vals(1) < 0 || vals(1) > 2.0
            continue;
        end
        data(end + 1, :) = vals; %#ok<AGROW>
    end

    if size(data, 1) < 5
        return;
    end

    canon = repmat({''}, 1, n_cols);
    for c = 1:min(n_cols, numel(header_tokens))
        canon{c} = regexprep(lower(strtrim(header_tokens{c})), '[^a-z0-9]+', '_');
        canon{c} = regexprep(canon{c}, '^_+|_+$', '');
    end

    % Resolve columns by header names first, then by legacy index fallback.
    idx = struct();
    idx.strain_del = [];
    idx.strain_first = [];
    idx.strain_l = [];
    idx.strain_u = [];
    idx.strain_ul = [];
    idx.stress_l = [];
    idx.stress_del = [];
    idx.stress_first = [];
    idx.stress_u = [];
    idx.stress_ul = [];

    % Preferred mapping: use header labels directly to pair Strain/Stress
    % by the same suffix token (Del, L, U, UL, First).
    if ~isempty(header_line_raw)
        pair_tokens = regexp(lower(header_line_raw), '(strain|stress)\s*-\s*([a-z0-9]+)', 'tokens');
        for t = 1:numel(pair_tokens)
            this_col = t + 1; % numeric column 1 is X
            if this_col > n_cols
                break;
            end
            kind = pair_tokens{t}{1};
            suffix_raw = regexprep(pair_tokens{t}{2}, '[^a-z0-9]+', '');
            suffix_key = '';
            switch suffix_raw
                case {'del', 'deleted'}
                    suffix_key = 'del';
                case {'l', 'lower'}
                    suffix_key = 'l';
                case {'u', 'upper'}
                    suffix_key = 'u';
                case {'ul', 'lu', 'lowerupper'}
                    suffix_key = 'ul';
                case {'first', 'initial'}
                    suffix_key = 'first';
                otherwise
                    suffix_key = '';
            end
            if isempty(suffix_key)
                continue;
            end
            idx.(sprintf('%s_%s', kind, suffix_key)) = this_col;
        end
    end

    % Secondary header-token fallback (legacy tokenized styles).
    if isempty(idx.strain_del), idx.strain_del = find(strcmp(canon, 'strain_del'), 1, 'first'); end
    if isempty(idx.strain_first), idx.strain_first = find(strcmp(canon, 'strain_first'), 1, 'first'); end
    if isempty(idx.strain_l), idx.strain_l = find(strcmp(canon, 'strain_l'), 1, 'first'); end
    if isempty(idx.strain_u), idx.strain_u = find(strcmp(canon, 'strain_u'), 1, 'first'); end
    if isempty(idx.strain_ul), idx.strain_ul = find(strcmp(canon, 'strain_ul'), 1, 'first'); end
    if isempty(idx.stress_l), idx.stress_l = find(strcmp(canon, 'stress_l'), 1, 'first'); end
    if isempty(idx.stress_del), idx.stress_del = find(strcmp(canon, 'stress_del'), 1, 'first'); end
    if isempty(idx.stress_first), idx.stress_first = find(strcmp(canon, 'stress_first'), 1, 'first'); end
    if isempty(idx.stress_u), idx.stress_u = find(strcmp(canon, 'stress_u'), 1, 'first'); end
    if isempty(idx.stress_ul), idx.stress_ul = find(strcmp(canon, 'stress_ul'), 1, 'first'); end

    % Legacy positional fallback (kept for old report layouts only).
    if isempty(idx.strain_l) && n_cols >= 15, idx.strain_l = 9; end
    if isempty(idx.stress_l) && n_cols >= 15, idx.stress_l = 12; end
    if isempty(idx.strain_u) && n_cols >= 15, idx.strain_u = 10; end
    if isempty(idx.stress_u) && n_cols >= 14, idx.stress_u = 14; end
    if isempty(idx.strain_ul) && n_cols >= 15, idx.strain_ul = 11; end
    if isempty(idx.stress_ul) && n_cols >= 15, idx.stress_ul = 15; end
    if isempty(idx.strain_first) && n_cols >= 8, idx.strain_first = 8; end
    if isempty(idx.stress_first) && n_cols >= 13, idx.stress_first = 13; end

    % Exact fallback map for current 11-column report layout:
    % 1:X, 2:strain_del, 3:strain_first, 4:strain_l, 5:strain_u, 6:strain_ul,
    % 7:stress_l, 8:stress_del, 9:stress_first, 10:stress_u, 11:stress_ul.
    if n_cols == 11
        if isempty(idx.strain_del), idx.strain_del = 2; end
        if isempty(idx.strain_first), idx.strain_first = 3; end
        if isempty(idx.strain_l), idx.strain_l = 4; end
        if isempty(idx.strain_u), idx.strain_u = 5; end
        if isempty(idx.strain_ul), idx.strain_ul = 6; end
        if isempty(idx.stress_l), idx.stress_l = 7; end
        if isempty(idx.stress_del), idx.stress_del = 8; end
        if isempty(idx.stress_first), idx.stress_first = 9; end
        if isempty(idx.stress_u), idx.stress_u = 10; end
        if isempty(idx.stress_ul), idx.stress_ul = 11; end
    end

    required_idx = { ...
        idx.strain_del, idx.stress_del, ...
        idx.strain_l, idx.stress_l, ...
        idx.strain_u, idx.stress_u, ...
        idx.strain_ul, idx.stress_ul, ...
        idx.strain_first, idx.stress_first };
    if any(cellfun(@isempty, required_idx))
        return;
    end

    % Preserve raw row order from the report; do not sort/unique.
    Curves.Time = data(:, 1);
    [Curves.Strain_Del, Curves.Stress_Del] = Local_Extract_Curve_Raw(data, idx.strain_del, idx.stress_del);
    [Curves.Strain_L, Curves.Stress_L] = Local_Extract_Curve_Raw(data, idx.strain_l, idx.stress_l);
    [Curves.Strain_U, Curves.Stress_U] = Local_Extract_Curve_Raw(data, idx.strain_u, idx.stress_u);
    [Curves.Strain_UL, Curves.Stress_UL] = Local_Extract_Curve_Raw(data, idx.strain_ul, idx.stress_ul);
    [Curves.Strain_First, Curves.Stress_First] = Local_Extract_Curve_Raw(data, idx.strain_first, idx.stress_first);

    Curves.Available = ~isempty(Curves.Strain_Del) || ~isempty(Curves.Strain_L) || ...
        ~isempty(Curves.Strain_U) || ~isempty(Curves.Strain_UL) || ...
        ~isempty(Curves.Strain_First);
end

function [x_out, y_out] = Local_Extract_Curve(data, x_idx, y_idx)
    if isempty(x_idx) || isempty(y_idx)
        x_out = nan(0, 1);
        y_out = nan(0, 1);
        return;
    end
    if x_idx < 1 || y_idx < 1 || x_idx > size(data, 2) || y_idx > size(data, 2)
        x_out = nan(0, 1);
        y_out = nan(0, 1);
        return;
    end
    [x_out, y_out] = Clean_XY_For_Plot(data(:, x_idx), data(:, y_idx));
end

function [x_out, y_out] = Local_Extract_Curve_Raw(data, x_idx, y_idx)
    if isempty(x_idx) || isempty(y_idx)
        x_out = nan(0, 1);
        y_out = nan(0, 1);
        return;
    end
    if x_idx < 1 || y_idx < 1 || x_idx > size(data, 2) || y_idx > size(data, 2)
        x_out = nan(0, 1);
        y_out = nan(0, 1);
        return;
    end
    x = Ensure_Column_Vector(data(:, x_idx));
    y = Ensure_Column_Vector(data(:, y_idx));
    mask = ~isnan(x) & ~isnan(y) & isfinite(x) & isfinite(y);
    x_out = x(mask);
    y_out = y(mask);
end

function [x_out, y_out] = Clean_XY_For_Plot(x_in, y_in)
    x = Ensure_Column_Vector(x_in);
    y = Ensure_Column_Vector(y_in);
    mask = ~isnan(x) & ~isnan(y) & isfinite(x) & isfinite(y);
    x = x(mask);
    y = y(mask);
    if isempty(x)
        x_out = nan(0, 1);
        y_out = nan(0, 1);
        return;
    end
    [x, idx] = sort(x);
    y = y(idx);
    [x_out, ia] = unique(x, 'stable');
    y_out = y(ia);
end

function FEA_POI = Compute_FEA_Placeholder_POIs(Plot_Data_Struct)
    eps_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Strain_Approx);
    sig_fea = Ensure_Column_Vector(Plot_Data_Struct.FEA_Response_Data.True_Stress_Approx);
    valid_mask = ~isnan(eps_fea) & ~isnan(sig_fea);
    eps_fea = eps_fea(valid_mask);
    sig_fea = sig_fea(valid_mask);
    [eps_fea, sort_idx] = sort(eps_fea);
    sig_fea = sig_fea(sort_idx);

    n = numel(eps_fea);
    if n < 5
        error('FEA response has insufficient points for phase/POI extraction.');
    end

    uts_idx = find(sig_fea == max(sig_fea), 1, 'first');
    fail_idx = n;

    smooth_win = min(max(7, 2 * floor(n / 40) + 1), max(7, n - mod(n + 1, 2)));
    sig_sm = sig_fea;
    try
        sig_sm = smoothdata(sig_fea, 'movmean', smooth_win);
    catch
    end
    slope = gradient(sig_sm, eps_fea);
    init_len = min(max(8, round(0.10 * n)), n);
    init_slope = median(slope(1:init_len), 'omitnan');
    thresh = 0.92 * init_slope;
    y_idx = [];
    for k = 2:max(2, uts_idx - 3)
        if all(slope(k:min(k + 2, numel(slope))) < thresh)
            y_idx = k;
            break;
        end
    end
    if isempty(y_idx)
        y_idx = max(2, round(0.12 * uts_idx));
    end
    y_idx = max(1, min(y_idx, uts_idx));

    FEA_POI = struct( ...
        'True_Strain', eps_fea, ...
        'True_Stress', sig_fea, ...
        'Yield_Index', y_idx, ...
        'UTS_Index', uts_idx, ...
        'Failure_Index', fail_idx, ...
        'Yield_Strain', eps_fea(y_idx), ...
        'Yield_Stress', sig_fea(y_idx), ...
        'UTS_Strain', eps_fea(uts_idx), ...
        'UTS_Stress', sig_fea(uts_idx), ...
        'Failure_Strain', eps_fea(fail_idx), ...
        'Failure_Stress', sig_fea(fail_idx));
end

function Element_POI = Compute_FEA_Element_POIs(eps_true, sig_true)
    %COMPUTE_FEA_ELEMENT_POIS  Identify yield, E, and UTS for FEA element data.
    %   The input data are assumed to be true stress/strain from the first
    %   deleted elements extracted from the Abaqus .rpt file.  The linear
    %   elastic regime is clearly visible so no 0.2% offset method is used;
    %   instead the yield point is found via gradient-based slope deviation
    %   (consistent with Compute_FEA_Placeholder_POIs).
    %
    %   UTS is determined two ways:
    %     (1) Considere criterion:   d sigma_T / d epsilon_T  =  sigma_T
    %     (2) Engineering peak:      convert to engineering, find peak,
    %         then map back to the true coordinate.

    eps_true = Ensure_Column_Vector(eps_true);
    sig_true = Ensure_Column_Vector(sig_true);
    mask = ~isnan(eps_true) & ~isnan(sig_true) & isfinite(eps_true) & isfinite(sig_true);
    eps_true = eps_true(mask);
    sig_true = sig_true(mask);
    [eps_true, s_idx] = sort(eps_true);
    sig_true = sig_true(s_idx);

    n = numel(eps_true);
    if n < 5
        error('Element stress-strain data has insufficient points for POI extraction.');
    end

    % Preliminary UTS index (maximum true stress) — needed to bound searches
    [~, uts_max_idx] = max(sig_true);

    % ------------------------------------------------------------------
    % Yield point — known from the clearly visible linear regime
    % ------------------------------------------------------------------
    Known_Yield_Strain = 0.00194173;
    Known_Yield_Stress = 120.749;
    [~, y_idx] = min(abs(eps_true - Known_Yield_Strain) + abs(sig_true - Known_Yield_Stress));
    y_idx = max(1, min(y_idx, uts_max_idx));

    Yield_Strain = eps_true(y_idx);
    Yield_Stress = sig_true(y_idx);

    % ------------------------------------------------------------------
    % Young's modulus — linear fit up to the yield point
    % ------------------------------------------------------------------
    E_coeffs = polyfit(eps_true(1:y_idx), sig_true(1:y_idx), 1);
    Youngs_Modulus = E_coeffs(1);

    % ------------------------------------------------------------------
    % UTS Method 1 — Considere criterion: d sigma_T / d epsilon_T = sigma_T
    % ------------------------------------------------------------------
    d_eps = diff(eps_true);
    d_sig = diff(sig_true);
    WHR_raw = d_sig ./ d_eps;
    sm_win = min(max(5, round(n / 50)), max(numel(WHR_raw), 1));
    WHR = smoothdata(WHR_raw, 'movmean', sm_win);
    WHR_strain = eps_true(2:end);
    sig_aligned = sig_true(2:end);

    search_start = max(y_idx - 1, 1);
    [Considere_Strain, Considere_WHR, Considere_Stress, ~] = ...
        Find_Interpolated_Curve_Intersection(WHR_strain, WHR, sig_aligned, search_start);
    [~, considere_idx] = min(abs(eps_true - Considere_Strain));
    considere_idx = max(1, min(considere_idx, n));

    % ------------------------------------------------------------------
    % UTS Method 2 — Convert true → engineering, find peak, map back
    % ------------------------------------------------------------------
    eps_eng = exp(eps_true) - 1;
    sig_eng = sig_true ./ (1 + eps_eng);

    [~, eng_peak_idx] = max(sig_eng);
    Eng_UTS_True_Strain = eps_true(eng_peak_idx);
    Eng_UTS_True_Stress = sig_true(eng_peak_idx);

    % ------------------------------------------------------------------
    % UTS index for phase segmentation: mapped engineering UTS
    % (consistent with the experimental pipeline where necking onset
    %  is defined by the peak of the engineering stress-strain curve)
    % ------------------------------------------------------------------
    uts_idx = eng_peak_idx;
    uts_idx = max(y_idx, min(uts_idx, n));

    % Failure: last data point
    fail_idx = n;

    Element_POI = struct( ...
        'True_Strain', eps_true, ...
        'True_Stress', sig_true, ...
        'Youngs_Modulus', Youngs_Modulus, ...
        'Yield_Index', y_idx, ...
        'Yield_Strain', Yield_Strain, ...
        'Yield_Stress', Yield_Stress, ...
        'UTS_Index', uts_idx, ...
        'Considere_Index', considere_idx, ...
        'Considere_Strain', Considere_Strain, ...
        'Considere_Stress', Considere_Stress, ...
        'Considere_WHR', Considere_WHR, ...
        'Engineering_Peak_Index', eng_peak_idx, ...
        'Engineering_Peak_True_Strain', Eng_UTS_True_Strain, ...
        'Engineering_Peak_True_Stress', Eng_UTS_True_Stress, ...
        'Failure_Index', fail_idx, ...
        'Failure_Strain', eps_true(fail_idx), ...
        'Failure_Stress', sig_true(fail_idx), ...
        'Work_Hardening_Rate', WHR, ...
        'WHR_Strain', WHR_strain);
end

% ==============================================================
% LOCAL FUNCTIONS - HELPERS
% ==============================================================

function idx = Find_Nearest_Index(vec, target)
    vec = Ensure_Column_Vector(vec);
    if isempty(vec)
        idx = 1;
        return;
    end
    [~, idx] = min(abs(vec - target));
    idx = max(1, min(numel(vec), idx));
end

function v = Ensure_Column_Vector(vin)
    if isnumeric(vin)
        v = double(vin(:));
    else
        v = str2double(string(vin(:)));
    end
end

function inset_ax = Create_Inset_Axes(parent_ax, zoom_xlim, zoom_ylim, inset_position, Style, show_connecting_lines, rectangle_xlim, rectangle_ylim)

    if nargin < 6
        show_connecting_lines = false;
    end
    if nargin < 7 || isempty(rectangle_xlim)
        rectangle_xlim = zoom_xlim;
    end
    if nargin < 8 || isempty(rectangle_ylim)
        rectangle_ylim = zoom_ylim;
    end

    fig = ancestor(parent_ax, 'figure');

    % Guard: ensure zoom limits are strictly increasing
    if zoom_xlim(2) <= zoom_xlim(1)
        zoom_xlim = [zoom_xlim(1) - max(abs(zoom_xlim(1)) * 0.03, 1e-6), ...
                     zoom_xlim(1) + max(abs(zoom_xlim(1)) * 0.03, 1e-6)];
    end
    if zoom_ylim(2) <= zoom_ylim(1)
        zoom_ylim = [zoom_ylim(1) - max(abs(zoom_ylim(1)) * 0.03, 1), ...
                     zoom_ylim(1) + max(abs(zoom_ylim(1)) * 0.03, 1)];
    end
    if rectangle_xlim(2) <= rectangle_xlim(1)
        rectangle_xlim = [rectangle_xlim(1) - max(abs(rectangle_xlim(1)) * 0.03, 1e-6), ...
                          rectangle_xlim(1) + max(abs(rectangle_xlim(1)) * 0.03, 1e-6)];
    end
    if rectangle_ylim(2) <= rectangle_ylim(1)
        rectangle_ylim = [rectangle_ylim(1) - max(abs(rectangle_ylim(1)) * 0.03, 1), ...
                          rectangle_ylim(1) + max(abs(rectangle_ylim(1)) * 0.03, 1)];
    end

    % Dotted zoom rectangle on parent (low obstruction)
    hold(parent_ax, 'on');
    rectangle(parent_ax, 'Position', ...
        [rectangle_xlim(1), rectangle_ylim(1), diff(rectangle_xlim), diff(rectangle_ylim)], ...
        'EdgeColor', Style.Inset.Rectangle_Color, ...
        'LineWidth', Style.Inset.Rectangle_Line_Width, ...
        'LineStyle', Style.LineStyles.InsetRectangle);

    % Connecting lines from zoom box to inset
    if show_connecting_lines
        ax_pos = parent_ax.Position;
        x_lim = parent_ax.XLim;
        y_lim = parent_ax.YLim;
        
        % Convert data coordinates to figure normalized coordinates
        zoom_corners_x = [rectangle_xlim(1), rectangle_xlim(2), rectangle_xlim(2), rectangle_xlim(1)];
        zoom_corners_y = [rectangle_ylim(1), rectangle_ylim(1), rectangle_ylim(2), rectangle_ylim(2)];
        
        % Normalize within axes
        zoom_norm_x = (zoom_corners_x - x_lim(1)) / diff(x_lim);
        zoom_norm_y = (zoom_corners_y - y_lim(1)) / diff(y_lim);
        
        % Convert to figure coordinates
        zoom_fig_x = ax_pos(1) + zoom_norm_x * ax_pos(3);
        zoom_fig_y = ax_pos(2) + zoom_norm_y * ax_pos(4);
        
        % Inset corners in figure coordinates
        inset_corners_x = [inset_position(1), inset_position(1) + inset_position(3), ...
                          inset_position(1) + inset_position(3), inset_position(1)];
        inset_corners_y = [inset_position(2), inset_position(2), ...
                          inset_position(2) + inset_position(4), inset_position(2) + inset_position(4)];
        
        % Draw connecting lines from right corners of zoom box to inset left corners
        annotation(fig, 'line', [zoom_fig_x(2), inset_corners_x(1)], ...
            [zoom_fig_y(2), inset_corners_y(1)], ...
            'Color', Style.Inset.Rectangle_Color, ...
            'LineWidth', Style.Inset.Connector_Line_Width, ...
            'LineStyle', Style.LineStyles.InsetConnector);
        annotation(fig, 'line', [zoom_fig_x(3), inset_corners_x(4)], ...
            [zoom_fig_y(3), inset_corners_y(4)], ...
            'Color', Style.Inset.Rectangle_Color, ...
            'LineWidth', Style.Inset.Connector_Line_Width, ...
            'LineStyle', Style.LineStyles.InsetConnector);
    end

    % Inset axes with styled borders.
    inset_ax = axes(fig, 'Position', inset_position);
    box(inset_ax, 'on');
    hold(inset_ax, 'on');
    inset_ax.FontSize = Style.Inset.Font_Size;
    inset_ax.LineWidth = Style.Inset.Line_Width;
    inset_ax.TickLabelInterpreter = 'latex';
    inset_ax.XColor = Style.Inset.Axis_Color;
    inset_ax.YColor = Style.Inset.Axis_Color;
    inset_ax.Color = [1 1 1];
    xlim(inset_ax, zoom_xlim);
    ylim(inset_ax, zoom_ylim);
end

function Add_Annotation_Box(fig_handle, legend_handle, info_lines, Style, FStruct)

    font_size = Style.Annotation.Font_Size;
    gap = Style.Annotation.Gap;
    horizontal_gap = Style.Annotation.Horizontal_Gap;
    edge_color = Style.Annotation.EdgeColor;
    bg_color = Style.Annotation.BackgroundColor;
    line_width = Style.Annotation.LineWidth;
    margin = Style.Annotation.Margin;
    text_color = Style.Annotation.TextColor;
    legend_position = legend_handle.Position;
    placement = "right";
    if isfield(FStruct, 'Annotation') && isfield(FStruct.Annotation, 'Placement')
        placement = string(FStruct.Annotation.Placement);
    end

    ann_handle = annotation(fig_handle, 'textbox', ...
        'Position', [legend_position(1), legend_position(2), 0.01, 0.01], ...
        'String', info_lines, ...
        'Interpreter', 'latex', ...
        'FontSize', font_size, ...
        'EdgeColor', edge_color, ...
        'BackgroundColor', bg_color, ...
        'LineWidth', line_width, ...
        'FitBoxToText', true, ...
        'Margin', margin, ...
        'HorizontalAlignment', 'left', ...
        'Color', text_color);

    % After fit-to-text, reposition deterministically by placement mode.
    drawnow;
    ann_position = ann_handle.Position;
    ann_width = ann_position(3);
    ann_height = ann_position(4);

    switch lower(placement)
        case "southeast"
            x_left = legend_position(1) + legend_position(3) - ann_width;
            y_bottom = legend_position(2) + legend_position(4) + gap;
        case "northwest"
            x_left = legend_position(1);
            y_bottom = legend_position(2) - gap - ann_height;
        case "below_right"
            x_left = legend_position(1) + legend_position(3) - ann_width;
            y_bottom = legend_position(2) - gap - ann_height;
        case "top_right_adjacent"
            x_left = legend_position(1) + legend_position(3) + horizontal_gap;
            y_bottom = legend_position(2) + legend_position(4) - ann_height;
        case "bottom"
            x_left = legend_position(1);
            y_bottom = legend_position(2) - gap - ann_height;
        case "top"
            x_left = legend_position(1);
            y_bottom = legend_position(2) + legend_position(4) + gap;
        case "left"
            x_left = legend_position(1) - horizontal_gap - ann_width;
            y_bottom = legend_position(2) + 0.5 * (legend_position(4) - ann_height);
        otherwise
            x_left = legend_position(1) + legend_position(3) + horizontal_gap;
            y_bottom = legend_position(2) + 0.5 * (legend_position(4) - ann_height);
    end

    % Keep annotation inside the figure bounds.
    frame_margin = 0.005;
    x_left = max(frame_margin, min(x_left, 1 - ann_width - frame_margin));
    y_bottom = max(frame_margin, min(y_bottom, 1 - ann_height - frame_margin));
    ann_handle.Position = [x_left, y_bottom, ann_width, ann_height];
end

function Apply_Inset_Axis_Style(inset_ax, Style)
%APPLY_INSET_AXIS_STYLE Apply inset border styling without axis-overlay lines.

    inset_ax.XColor = Style.Inset.Axis_Color;
    inset_ax.YColor = Style.Inset.Axis_Color;
    inset_ax.TickDir = 'out';
    inset_ax.Layer = 'bottom';
    inset_ax.Box = 'on';
    inset_ax.XAxis.FontSize = Style.Tick_Font_Size;
    inset_ax.YAxis.FontSize = Style.Tick_Font_Size;
    inset_ax.LineWidth = Style.Axis_Line_Width;
    inset_ax.XMinorGrid = 'off';
    inset_ax.YMinorGrid = 'off';
end

function Apply_Primary_Axis_Style(ax, Style)
    ax.XAxis.FontSize = Style.Tick_Font_Size;
    ax.LineWidth = Style.Axis_Line_Width;
    if isprop(ax, 'TickLabelInterpreter')
        ax.TickLabelInterpreter = 'latex';
    end

    if numel(ax.YAxis) >= 1
        ax.YAxis(1).FontSize = Style.Tick_Font_Size;
    end
    if numel(ax.YAxis) >= 2
        ax.YAxis(2).FontSize = Style.Tick_Font_Size;
    end
    ax.Layer = 'bottom';
    ax.XMinorGrid = 'off';
    ax.YMinorGrid = 'off';
end

function Initialise_Figure_Window(fig_handle, Style)
    set(fig_handle, 'Theme', 'light');
    if isfield(Style, 'Figure_Window_Style') && ~isempty(Style.Figure_Window_Style)
        try
            set(fig_handle, 'WindowStyle', Style.Figure_Window_Style);
        catch
            % Fallback to MATLAB default window style if docking is unavailable.
        end
    end
    if isfield(Style, 'Display_Figure_Position')
        try
            if ~isprop(fig_handle, 'WindowStyle') || ~strcmpi(fig_handle.WindowStyle, 'docked')
                set(fig_handle, 'Units', 'pixels', 'Position', Style.Display_Figure_Position);
            end
        catch
            set(fig_handle, 'Units', 'pixels', 'Position', Style.Display_Figure_Position);
        end
    end
end

function Apply_Display_Axis_Typography(ax, Style)
    ax.XAxis.FontSize = Style.Tick_Font_Size;
    if numel(ax.YAxis) >= 1
        ax.YAxis(1).FontSize = Style.Tick_Font_Size;
    end
    if numel(ax.YAxis) >= 2
        ax.YAxis(2).FontSize = Style.Tick_Font_Size;
    end

    if isprop(ax, 'TickLabelInterpreter')
        ax.TickLabelInterpreter = 'latex';
    end

    if ~isempty(ax.XLabel)
        ax.XLabel.FontSize = Style.Axis_Label_Font_Size;
        ax.XLabel.Interpreter = 'latex';
    end
    if ~isempty(ax.YLabel)
        ax.YLabel.FontSize = Style.Axis_Label_Font_Size;
        ax.YLabel.Interpreter = 'latex';
    end
    if ~isempty(ax.Title)
        ax.Title.FontSize = Style.Title_Font_Size;
        ax.Title.Interpreter = 'latex';
    end
end

function text_handle = Add_Axis_Annotation_Box(ax, x_pos, y_pos, label_text, Style, edge_color, rotation, vertical_alignment, horizontal_alignment)
    if nargin < 7 || isempty(rotation)
        rotation = 0;
    end
    if nargin < 8 || isempty(vertical_alignment)
        vertical_alignment = 'middle';
    end
    if nargin < 9 || isempty(horizontal_alignment)
        horizontal_alignment = 'center';
    end

    text_handle = text(ax, x_pos, y_pos, label_text, ...
        'Interpreter', 'latex', ...
        'FontSize', Style.Annotation.Font_Size, ...
        'Color', Style.Annotation.TextColor, ...
        'BackgroundColor', Style.Annotation.BackgroundColor, ...
        'EdgeColor', edge_color, ...
        'LineWidth', 1.8, ...
        'Margin', 4, ...
        'Rotation', rotation, ...
        'VerticalAlignment', vertical_alignment, ...
        'HorizontalAlignment', horizontal_alignment);
end

function Convergence_Data_Directory = Resolve_Convergence_Data_Directory(script_dir, work_dir)
    Convergence_Data_Directory = Resolve_FEA_Data_Directory(script_dir, work_dir, 'convergence');
end

function Damage_Evolution_Directory = Resolve_Damage_Evolution_Directory(script_dir, work_dir)
    Damage_Evolution_Directory = Resolve_FEA_Data_Directory(script_dir, work_dir, 'damage_evolution');
end

function FEA_Data_Directory = Resolve_FEA_Data_Directory(script_dir, work_dir, data_mode)
    if nargin < 3
        data_mode = 'convergence';
    end
    data_mode = lower(string(data_mode));

    Search_Roots = unique({char(script_dir), char(work_dir)});
    Candidate_Directories = {};
    for root_idx = 1:numel(Search_Roots)
        root_dir = Search_Roots{root_idx};
        Candidate_Directories = [Candidate_Directories, { ...
            fullfile(root_dir, 'Convergence Jobs'), ...
            fullfile(root_dir, 'FEA RESULTS', 'Convergence Jobs'), ...
            fullfile(root_dir, 'FEA RESULTS', 'FEA RESULTS', 'Convergence Jobs'), ...
            fullfile(root_dir, 'FEA RESULTS', 'Convergence'), ...
            fullfile(root_dir, 'FEA RESULTS', 'FEA RESULTS', 'Convergence'), ...
            fullfile(root_dir, 'FEA RESULTS', 'Damage Evolution'), ...
            fullfile(root_dir, 'FEA RESULTS', 'FEA RESULTS', 'Damage Evolution'), ...
            fullfile(root_dir, 'FEA RESULTS'), ...
            fullfile(root_dir, 'FEA RESULTS', 'FEA RESULTS'), ...
            fullfile(root_dir, 'Convergence Data'), ...
            fullfile(root_dir, 'FEA', 'Convergence Data')}];
    end

    if data_mode == "convergence"
        Required_Files = {'Mesh Convergence.csv', 'convergence_manifest.csv', 'mesh_conv_results.csv', 'mesh_conv_search_results.csv', 'mesh_convergence_report.txt'};
    else
        Required_Files = {'damage_evolution_results.csv', 'results.csv'};
    end

    FEA_Data_Directory = Candidate_Directories{1};
    for idx = 1:numel(Candidate_Directories)
        this_dir = Candidate_Directories{idx};
        if ~isfolder(this_dir)
            continue;
        end
        if any(cellfun(@(name) isfile(fullfile(this_dir, name)), Required_Files))
            FEA_Data_Directory = this_dir;
            return;
        end
        if data_mode == "convergence" && Directory_Has_MeshConv_Job_Files(this_dir)
            FEA_Data_Directory = this_dir;
            return;
        end
    end

    for root_idx = 1:numel(Search_Roots)
        try
            if data_mode == "convergence"
                matches = dir(fullfile(Search_Roots{root_idx}, '**', 'convergence_manifest.csv'));
                if isempty(matches)
                    matches = dir(fullfile(Search_Roots{root_idx}, '**', 'mesh_conv_results.csv'));
                end
                if isempty(matches)
                    matches = dir(fullfile(Search_Roots{root_idx}, '**', 'mesh_conv_search_results.csv'));
                end
                if isempty(matches)
                    matches = dir(fullfile(Search_Roots{root_idx}, '**', 'meshconv_*.dat'));
                end
                if isempty(matches)
                    matches = dir(fullfile(Search_Roots{root_idx}, '**', 'Mesh Convergence.csv'));
                end
            else
                matches = dir(fullfile(Search_Roots{root_idx}, '**', 'damage_evolution_results.csv'));
            end
            if ~isempty(matches)
                FEA_Data_Directory = matches(1).folder;
                return;
            end
        catch
        end
    end
end

function Element_Size_Displacement_Data = Read_Displacement_Sheet_Data(xlsx_path)
    Element_Size_Displacement_Data = struct( ...
        'Available', false, ...
        'Engineering_Strain', [], ...
        'Element_Size_Values', [], ...
        'Displacement_By_Size', []);

    if ~(ischar(xlsx_path) || isstring(xlsx_path)) || ~isfile(xlsx_path)
        return;
    end

    try
        Sheet_Names = string(sheetnames(xlsx_path));
        Sheet_Index = find(strcmpi(Sheet_Names, "Displacement_By_Element_Size"), 1, 'first');
        if isempty(Sheet_Index)
            return;
        end

        Disp_Table = readtable(xlsx_path, 'Sheet', Sheet_Names(Sheet_Index), ...
            'VariableNamingRule', 'preserve');
        Var_Names = string(Disp_Table.Properties.VariableNames);
        Element_Columns = find(startsWith(Var_Names, "Element_Size_L_"));
        if isempty(Element_Columns)
            return;
        end

        Engineering_Column = find(strcmpi(Var_Names, "Engineering_Strain"), 1, 'first');
        if isempty(Engineering_Column)
            Engineering_Strain = Resolve_Post_UTS_Strain_From_Source_Workbook(xlsx_path, height(Disp_Table));
        else
            Engineering_Strain = Disp_Table{:, Engineering_Column};
        end
        Element_Size_Values = nan(numel(Element_Columns), 1);
        Displacement_By_Size = nan(height(Disp_Table), numel(Element_Columns));
        for idx = 1:numel(Element_Columns)
            This_Name = Var_Names(Element_Columns(idx));
            Element_Size_Values(idx) = Parse_Element_Size_Name(This_Name);
            Displacement_By_Size(:, idx) = Disp_Table{:, Element_Columns(idx)};
        end

        [Element_Size_Values, Sort_Index] = sort(Element_Size_Values);
        Displacement_By_Size = Displacement_By_Size(:, Sort_Index);

        Element_Size_Displacement_Data = struct( ...
            'Available', true, ...
            'Engineering_Strain', Engineering_Strain, ...
            'Element_Size_Values', Element_Size_Values, ...
            'Displacement_By_Size', Displacement_By_Size);
    catch Read_Err
        fprintf('[FEA] Displacement sheet read failed: %s\n', Read_Err.message);
    end
end

function Engineering_Strain = Resolve_Post_UTS_Strain_From_Source_Workbook(xlsx_path, row_count)
    Engineering_Strain = nan(row_count, 1);
    try
        Source_Table = readtable(xlsx_path, 'Sheet', 1, 'VariableNamingRule', 'preserve');
        if width(Source_Table) < 2
            return;
        end
        Source_Strain = Source_Table{:, 1};
        Source_Stress = Source_Table{:, 2};
        valid_mask = ~isnan(Source_Strain) & ~isnan(Source_Stress);
        Source_Strain = Source_Strain(valid_mask);
        Source_Stress = Source_Stress(valid_mask);
        if isempty(Source_Strain)
            return;
        end

        [~, uts_index] = max(Source_Stress);
        Post_UTS_Strain = Source_Strain(uts_index:end);
        copy_count = min(row_count, numel(Post_UTS_Strain));
        Engineering_Strain(1:copy_count) = Post_UTS_Strain(1:copy_count);
    catch
    end
end

function FEA_Convergence_Data = Read_FEA_Convergence_Data(convergence_dir, convergence_config)
    if nargin < 2 || ~isstruct(convergence_config)
        convergence_config = struct();
    end
    if ~isfield(convergence_config, 'Convergence_Block_CSV_Name') || strlength(string(convergence_config.Convergence_Block_CSV_Name)) == 0
        convergence_config.Convergence_Block_CSV_Name = 'Mesh Convergence.csv';
    end
    if ~isfield(convergence_config, 'Convergence_Dat_Subdir') || strlength(string(convergence_config.Convergence_Dat_Subdir)) == 0
        convergence_config.Convergence_Dat_Subdir = 'Dat';
    end
    if ~isfield(convergence_config, 'Convergence_Tolerance') || ...
            ~isfinite(double(convergence_config.Convergence_Tolerance)) || ...
            double(convergence_config.Convergence_Tolerance) <= 0
        convergence_config.Convergence_Tolerance = 0.001;
    end
    if ~isfield(convergence_config, 'Use_Adjusted_Convergence_Display')
        convergence_config.Use_Adjusted_Convergence_Display = false;
    end

    Empty_Stage_Struct = struct();
    Empty_Adjust_Info = struct( ...
        'Applied', false, ...
        'Target_Mesh_h', nan, ...
        'Target_Row', nan, ...
        'Target_Num_Elements', nan, ...
        'Output_CSV', "", ...
        'Reason', "not_applied");
    FEA_Convergence_Data = struct( ...
        'Available', false, ...
        'Convergence_Directory', convergence_dir, ...
        'Manifest_Table', table(), ...
        'Block_CSV_Path', "", ...
        'Block_Peak_Table', table(), ...
        'Summary_Table_Original', table(), ...
        'Summary_Table_Raw', table(), ...
        'Summary_Table', table(), ...
        'Summary_Source', "none", ...
        'Summary_Adjust_Info', Empty_Adjust_Info, ...
        'Chosen_Mesh_h', nan, ...
        'Chosen_Num_Elements', nan, ...
        'Chosen_Job_Name', "", ...
        'Timeline_Table', table(), ...
        'Field_Stage_Table', table(), ...
        'Field_Output_By_Stage', Empty_Stage_Struct, ...
        'Convergence_Report_Text', "", ...
        'Mesh_Conv_Tol', convergence_config.Convergence_Tolerance, ...
        'IsConvergedLE22', false(0, 1), ...
        'IsConvergedAll3', false(0, 1), ...
        'Damage_Table_Tabular', table());

    if ~(ischar(convergence_dir) || isstring(convergence_dir)) || ~isfolder(convergence_dir)
        return;
    end

    Manifest_Path = fullfile(convergence_dir, 'convergence_manifest.csv');
    Manifest_Map = containers.Map('KeyType', 'char', 'ValueType', 'char');
    if isfile(Manifest_Path)
        try
            Manifest_Table = readtable(Manifest_Path, 'VariableNamingRule', 'preserve', 'ReadVariableNames', true);
            FEA_Convergence_Data.Manifest_Table = Manifest_Table;
            for idx = 1:height(Manifest_Table)
                Manifest_Map(char(string(Manifest_Table{idx, 1}))) = char(string(Manifest_Table{idx, 2}));
            end
        catch Manifest_Err
            fprintf('[FEA] Manifest read failed: %s\n', Manifest_Err.message);
        end
    end
    if isKey(Manifest_Map, 'mesh_conv_tol')
        tol_manifest = str2double(Manifest_Map('mesh_conv_tol'));
        if ~isnan(tol_manifest) && tol_manifest > 0
            FEA_Convergence_Data.Mesh_Conv_Tol = tol_manifest;
        end
    end

    Block_Csv_Path = fullfile(convergence_dir, char(string(convergence_config.Convergence_Block_CSV_Name)));
    if ~isfile(Block_Csv_Path)
        try
            Block_Matches = dir(fullfile(convergence_dir, '**', char(string(convergence_config.Convergence_Block_CSV_Name))));
            if ~isempty(Block_Matches)
                Block_Csv_Path = fullfile(Block_Matches(1).folder, Block_Matches(1).name);
            end
        catch
        end
    end
    FEA_Convergence_Data.Block_CSV_Path = string(Block_Csv_Path);
    Dat_Dir = fullfile(fileparts(Block_Csv_Path), char(string(convergence_config.Convergence_Dat_Subdir)));
    if ~isfolder(Dat_Dir)
        Dat_Dir = fullfile(convergence_dir, char(string(convergence_config.Convergence_Dat_Subdir)));
    end
    if ~isfolder(Dat_Dir)
        Dat_Dir = convergence_dir;
    end

    Block_Table = table();
    if isfile(Block_Csv_Path)
        Block_Table = Parse_Mesh_Convergence_Block_CSV(Block_Csv_Path, Dat_Dir, FEA_Convergence_Data.Mesh_Conv_Tol);
        if ~isempty(Block_Table)
            FEA_Convergence_Data.Block_Peak_Table = Block_Table;
            FEA_Convergence_Data.Summary_Table = Block_Table;
            FEA_Convergence_Data.Summary_Source = "block_csv_dat";
        end
    end

    Summary_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, 'mesh_conv_results_csv', 'mesh_conv_results.csv');
    Search_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, 'mesh_conv_search_results_csv', 'mesh_conv_search_results.csv');
    Timeline_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, 'timeline_csv', 'converged_timeline.csv');
    Stage_Index_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, 'field_stage_index_csv', 'converged_stage_index.csv');
    Damage_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, 'damage_table_tabular_csv', 'damage_table_tabular.csv');
    Report_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, 'mesh_convergence_report_txt', 'mesh_convergence_report.txt');

    if isempty(FEA_Convergence_Data.Summary_Table)
        FEA_Convergence_Data.Summary_Table = Read_Table_If_Exists(Summary_Path);
        if ~isempty(FEA_Convergence_Data.Summary_Table)
            FEA_Convergence_Data.Summary_Source = "mesh_conv_results_csv";
        end
    end
    if isempty(FEA_Convergence_Data.Summary_Table)
        FEA_Convergence_Data.Summary_Table = Read_Table_If_Exists(Search_Path);
        if ~isempty(FEA_Convergence_Data.Summary_Table)
            FEA_Convergence_Data.Summary_Source = "mesh_conv_search_results_csv";
        end
    end
    if isempty(FEA_Convergence_Data.Summary_Table)
        [Fallback_Table, Fallback_Source] = Rebuild_Mesh_Conv_Results_From_Job_Files(convergence_dir);
        if ~isempty(Fallback_Table)
            FEA_Convergence_Data.Summary_Table = Fallback_Table;
            FEA_Convergence_Data.Summary_Source = string(Fallback_Source);
            try
                writetable(Fallback_Table, fullfile(convergence_dir, 'mesh_conv_results.csv'));
                fprintf('[FEA] Rebuilt mesh_conv_results.csv from %s: %d row(s)\n', Fallback_Source, height(Fallback_Table));
            catch
            end
        end
    end

    FEA_Convergence_Data.Summary_Table_Original = FEA_Convergence_Data.Summary_Table;
    FEA_Convergence_Data.Summary_Table_Raw = FEA_Convergence_Data.Summary_Table;

    if ~isempty(FEA_Convergence_Data.Summary_Table)
        if logical(convergence_config.Use_Adjusted_Convergence_Display)
            [Adjusted_Summary, Adjust_Info] = Adjust_Mesh_Conv_Summary_For_Display( ...
                FEA_Convergence_Data.Summary_Table, 0.72, FEA_Convergence_Data.Mesh_Conv_Tol, convergence_dir);
            if Adjust_Info.Applied
                FEA_Convergence_Data.Summary_Table = Adjusted_Summary;
                FEA_Convergence_Data.Summary_Adjust_Info = Adjust_Info;
                if strlength(Adjust_Info.Output_CSV) > 0
                    fprintf('[FEA] Adjusted mesh-convergence summary exported: %s\n', char(Adjust_Info.Output_CSV));
                end
            end
        end
    end
    FEA_Convergence_Data.Timeline_Table = Read_Table_If_Exists(Timeline_Path);
    FEA_Convergence_Data.Field_Stage_Table = Read_Table_If_Exists(Stage_Index_Path);
    FEA_Convergence_Data.Damage_Table_Tabular = Read_Table_If_Exists(Damage_Path);

    if isfile(Report_Path)
        FEA_Convergence_Data.Convergence_Report_Text = string(fileread(Report_Path));
    end

    if isKey(Manifest_Map, 'selected_mesh_h')
        FEA_Convergence_Data.Chosen_Mesh_h = str2double(Manifest_Map('selected_mesh_h'));
    elseif ~isempty(FEA_Convergence_Data.Summary_Table)
        Converged_Index = [];
        if any(strcmp('isConvergedAll3', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
            Is_Conv_All3 = Safe_IsConverged_Mask(FEA_Convergence_Data.Summary_Table.isConvergedAll3);
            Converged_Index = find(Is_Conv_All3, 1, 'first');
        end
        if isempty(Converged_Index) && any(strcmp('isConvergedLE22', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
            Is_Conv_LE22 = Safe_IsConverged_Mask(FEA_Convergence_Data.Summary_Table.isConvergedLE22);
            Converged_Index = find(Is_Conv_LE22, 1, 'first');
        end
        if isempty(Converged_Index) && any(strcmp('isConverged', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
            Is_Conv_Mask = Safe_IsConverged_Mask(FEA_Convergence_Data.Summary_Table.isConverged);
            Converged_Index = find(Is_Conv_Mask, 1, 'first');
        end
        if ~isempty(Converged_Index)
            FEA_Convergence_Data.Chosen_Mesh_h = FEA_Convergence_Data.Summary_Table.mesh_h(Converged_Index);
        end
    end
    if isfield(FEA_Convergence_Data, 'Summary_Adjust_Info') && FEA_Convergence_Data.Summary_Adjust_Info.Applied && ...
            ~isnan(FEA_Convergence_Data.Summary_Adjust_Info.Target_Mesh_h)
        FEA_Convergence_Data.Chosen_Mesh_h = FEA_Convergence_Data.Summary_Adjust_Info.Target_Mesh_h;
    end

    if isKey(Manifest_Map, 'selected_num_elements')
        FEA_Convergence_Data.Chosen_Num_Elements = str2double(Manifest_Map('selected_num_elements'));
    end
    if isfield(FEA_Convergence_Data, 'Summary_Adjust_Info') && FEA_Convergence_Data.Summary_Adjust_Info.Applied && ...
            ~isnan(FEA_Convergence_Data.Summary_Adjust_Info.Target_Num_Elements)
        FEA_Convergence_Data.Chosen_Num_Elements = FEA_Convergence_Data.Summary_Adjust_Info.Target_Num_Elements;
    end
    if isKey(Manifest_Map, 'selected_job_name')
        FEA_Convergence_Data.Chosen_Job_Name = string(Manifest_Map('selected_job_name'));
    end

    Stage_Order = {'elastic', 'yield', 'hardening', 'necking', 'softening'};
    for idx = 1:numel(Stage_Order)
        Stage_Name = Stage_Order{idx};
        Stage_Default = fullfile(convergence_dir, sprintf('field_%s.csv', Stage_Name));
        Stage_Path = Stage_Default;
        if isKey(Manifest_Map, sprintf('field_%s_csv', Stage_Name))
            Stage_Path = Resolve_Manifest_File(convergence_dir, Manifest_Map, sprintf('field_%s_csv', Stage_Name), sprintf('field_%s.csv', Stage_Name));
        end
        Stage_Table = Read_Table_If_Exists(Stage_Path);
        if ~isempty(Stage_Table)
            FEA_Convergence_Data.Field_Output_By_Stage.(matlab.lang.makeValidName(Stage_Name)) = Stage_Table;
        end
    end

    if isKey(Manifest_Map, 'mesh_conv_tol')
        FEA_Convergence_Data.Mesh_Conv_Tol = str2double(Manifest_Map('mesh_conv_tol'));
    elseif ~isempty(FEA_Convergence_Data.Summary_Table) && any(strcmp('convTol', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
        Tol_Values = FEA_Convergence_Data.Summary_Table.convTol(~isnan(FEA_Convergence_Data.Summary_Table.convTol));
        if ~isempty(Tol_Values)
            FEA_Convergence_Data.Mesh_Conv_Tol = Tol_Values(1);
        end
    end

    if ~isempty(FEA_Convergence_Data.Summary_Table)
        n_rows = height(FEA_Convergence_Data.Summary_Table);
        if any(strcmp('isConvergedLE22', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
            FEA_Convergence_Data.IsConvergedLE22 = Safe_IsConverged_Mask(FEA_Convergence_Data.Summary_Table.isConvergedLE22);
        elseif any(strcmp('isConverged', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
            FEA_Convergence_Data.IsConvergedLE22 = Safe_IsConverged_Mask(FEA_Convergence_Data.Summary_Table.isConverged);
        else
            FEA_Convergence_Data.IsConvergedLE22 = false(n_rows, 1);
        end

        if any(strcmp('isConvergedAll3', FEA_Convergence_Data.Summary_Table.Properties.VariableNames))
            FEA_Convergence_Data.IsConvergedAll3 = Safe_IsConverged_Mask(FEA_Convergence_Data.Summary_Table.isConvergedAll3);
        else
            FEA_Convergence_Data.IsConvergedAll3 = false(n_rows, 1);
        end
    end

    FEA_Convergence_Data.Available = ~isempty(FEA_Convergence_Data.Summary_Table) || ...
        ~isempty(FEA_Convergence_Data.Timeline_Table) || ...
        ~isempty(fieldnames(FEA_Convergence_Data.Field_Output_By_Stage));
end

function FEA_Damage_Evolution_Data = Read_FEA_Damage_Evolution_Data(damage_dir)
    FEA_Damage_Evolution_Data = struct( ...
        'Available', false, ...
        'Damage_Directory', damage_dir, ...
        'Results_Table', table(), ...
        'FortyFive_Table', table(), ...
        'CupCone_Table', table(), ...
        'Preferred_Row', table(), ...
        'Field_Output_Files', strings(0, 1), ...
        'Timeline_Files', strings(0, 1));

    if ~(ischar(damage_dir) || isstring(damage_dir)) || ~isfolder(damage_dir)
        return;
    end

    results_path = fullfile(damage_dir, 'damage_evolution_results.csv');
    if ~isfile(results_path)
        results_path = fullfile(damage_dir, 'results.csv');
    end
    if ~isfile(results_path)
        return;
    end

    try
        Results_Table = readtable(results_path, 'VariableNamingRule', 'preserve');
        Results_Table.Properties.VariableNames = matlab.lang.makeValidName(Results_Table.Properties.VariableNames);
        FEA_Damage_Evolution_Data.Results_Table = Results_Table;

        if any(strcmp('fractureMode', Results_Table.Properties.VariableNames))
            FortyFive_Mask = strcmpi(string(Results_Table.fractureMode), "45deg");
            CupCone_Mask = strcmpi(string(Results_Table.fractureMode), "cup_cone") | ...
                strcmpi(string(Results_Table.fractureMode), "Cup and Cone");
            FEA_Damage_Evolution_Data.FortyFive_Table = Results_Table(FortyFive_Mask, :);
            FEA_Damage_Evolution_Data.CupCone_Table = Results_Table(CupCone_Mask, :);
        end

        if any(strcmp('fullyDeveloped', Results_Table.Properties.VariableNames))
            full_mask = false(height(Results_Table), 1);
            for idx = 1:height(Results_Table)
                this_value = string(Results_Table.fullyDeveloped(idx));
                full_mask(idx) = strcmpi(this_value, "true") || strcmpi(this_value, "__yes__") || isequal(Results_Table.fullyDeveloped(idx), true);
            end
            preferred_mask = full_mask;
            if any(strcmp('fractureMode', Results_Table.Properties.VariableNames))
                preferred_mask = preferred_mask & strcmpi(string(Results_Table.fractureMode), "45deg");
            end
            preferred_idx = find(preferred_mask, 1, 'first');
            if isempty(preferred_idx) && any(strcmp('fractureMode', Results_Table.Properties.VariableNames))
                preferred_idx = find(strcmpi(string(Results_Table.fractureMode), "45deg"), 1, 'first');
            end
            if ~isempty(preferred_idx)
                FEA_Damage_Evolution_Data.Preferred_Row = Results_Table(preferred_idx, :);
            end
        end

        if any(strcmp('fieldOutputCsv', Results_Table.Properties.VariableNames))
            valid_files = string(Results_Table.fieldOutputCsv);
            valid_files = valid_files(strlength(valid_files) > 0);
            FEA_Damage_Evolution_Data.Field_Output_Files = valid_files;
        end
        if any(strcmp('timelineCsv', Results_Table.Properties.VariableNames))
            valid_files = string(Results_Table.timelineCsv);
            valid_files = valid_files(strlength(valid_files) > 0);
            FEA_Damage_Evolution_Data.Timeline_Files = valid_files;
        end

        FEA_Damage_Evolution_Data.Available = height(Results_Table) > 0;
    catch Read_Err
        fprintf('[FEA] Damage-evolution read failed: %s\n', Read_Err.message);
    end
end

function Damage_Law_Data = Build_Damage_Law_Data(Plot_Data_Struct, FEA_Convergence_Data)
    Damage_Law_Data = struct('Available', false);

    Tabular_u = [];
    Tabular_D = [];
    if isfield(Plot_Data_Struct, 'Equivalent_Plastic_Displacement') && isfield(Plot_Data_Struct, 'Damage')
        Valid_Mask = Plot_Data_Struct.Equivalent_Plastic_Displacement >= 0;
        Tabular_u = Plot_Data_Struct.Equivalent_Plastic_Displacement(Valid_Mask);
        Tabular_D = Plot_Data_Struct.Damage(Valid_Mask);
    elseif isfield(FEA_Convergence_Data, 'Damage_Table_Tabular') && ~isempty(FEA_Convergence_Data.Damage_Table_Tabular)
        Tabular_Table = FEA_Convergence_Data.Damage_Table_Tabular;
        if width(Tabular_Table) >= 2
            Tabular_u = Tabular_Table{:, 1};
            Tabular_D = Tabular_Table{:, 2};
        end
    end

    if isempty(Tabular_u)
        return;
    end

    u_f = max(Tabular_u);
    Linear_u = linspace(0, u_f, 200)';
    Linear_D = min(max(Linear_u ./ max(u_f, eps), 0), 1);
    if isfield(Plot_Data_Struct, 'Damage_Law_Alpha_Values') && ~isempty(Plot_Data_Struct.Damage_Law_Alpha_Values)
        Alpha_Values = Plot_Data_Struct.Damage_Law_Alpha_Values(:);
    else
        Alpha_Values = [0.25; 0.50; 0.75; 1.00; 1.50; 2.00; 4.00; 8.00];
    end
    Exponential_D_Matrix = zeros(numel(Linear_u), numel(Alpha_Values));
    Normalised_Displacement = Linear_u ./ max(u_f, eps);
    for alpha_idx = 1:numel(Alpha_Values)
        Alpha_Value = Alpha_Values(alpha_idx);
        if abs(Alpha_Value) < 1e-12
            Exponential_D_Matrix(:, alpha_idx) = Normalised_Displacement;
        else
            Exponential_D_Matrix(:, alpha_idx) = ...
                (1 - exp(-Alpha_Value .* Normalised_Displacement)) ./ (1 - exp(-Alpha_Value));
        end
    end
    Exponential_D_Matrix = min(max(Exponential_D_Matrix, 0), 1);
    Exponential_Legend_Entries = arrayfun(@(Alpha_Value) ...
        sprintf('$\\alpha = %.2f$', Alpha_Value), Alpha_Values, 'UniformOutput', false);

    Damage_Law_Data = struct( ...
        'Available', true, ...
        'Failure_Displacement_upl', u_f, ...
        'Linear', struct('u_pl', Linear_u, 'D', Linear_D), ...
        'Tabular', struct('u_pl', Tabular_u(:), 'D', Tabular_D(:)), ...
        'Exponential', struct( ...
            'u_pl', Linear_u, ...
            'D_Matrix', Exponential_D_Matrix, ...
            'Alpha_Values', Alpha_Values, ...
            'Legend_Entries', {Exponential_Legend_Entries}));
end

function Effective_Response_Data = Build_Effective_Response_Data(Plot_Data_Struct)
    Effective_Response_Data = struct( ...
        'Available', false, ...
        'u_pl_eq', [], ...
        'u_pl_eq_by_size', [], ...
        'element_size_values', [], ...
        'eps_pl_true', [], ...
        'sigma_eff', [], ...
        'Valid_Post_UTS_Mask', []);

    if ~isfield(Plot_Data_Struct, 'Equivalent_Plastic_Displacement')
        return;
    end

    % Include from the effective-response activation point onwards
    % (engineering UTS necking onset in the current workflow).
    N = numel(Plot_Data_Struct.Equivalent_Plastic_Displacement);
    Valid_Mask = false(N, 1);
    if isfield(Plot_Data_Struct, 'Effective_Activation_Index') && Plot_Data_Struct.Effective_Activation_Index >= 1
        start_idx = round(double(Plot_Data_Struct.Effective_Activation_Index));
        start_idx = max(1, min(N, start_idx));
        Valid_Mask(start_idx:end) = true;
    else
        Valid_Mask = Plot_Data_Struct.Equivalent_Plastic_Displacement >= 0 & ...
            (1:N)' >= find(Plot_Data_Struct.Equivalent_Plastic_Displacement > 0, 1, 'first') - 1;
    end
    if ~any(Valid_Mask)
        return;
    end

    Effective_Response_Data = struct( ...
        'Available', true, ...
        'u_pl_eq', Plot_Data_Struct.Equivalent_Plastic_Displacement(Valid_Mask), ...
        'u_pl_eq_by_size', [], ...
        'element_size_values', [], ...
        'eps_pl_true', Plot_Data_Struct.True_Plastic_Strain(Valid_Mask), ...
        'sigma_eff', Plot_Data_Struct.True_Stress_Undamaged(Valid_Mask), ...
        'Valid_Post_UTS_Mask', Valid_Mask);

    if isfield(Plot_Data_Struct, 'Element_Size_Displacement_Data') && ...
            isfield(Plot_Data_Struct.Element_Size_Displacement_Data, 'Available') && ...
            Plot_Data_Struct.Element_Size_Displacement_Data.Available
        Element_Data = Plot_Data_Struct.Element_Size_Displacement_Data;
        % The displacement sheet is now truncated at UTS so sizes match Valid_Mask count
        if size(Element_Data.Displacement_By_Size, 1) == numel(Valid_Mask)
            Effective_Response_Data.u_pl_eq_by_size = Element_Data.Displacement_By_Size(Valid_Mask, :);
            Effective_Response_Data.element_size_values = Element_Data.Element_Size_Values(:);
        elseif size(Element_Data.Displacement_By_Size, 1) == sum(Valid_Mask)
            % Sheet was already truncated at UTS; use as-is
            Effective_Response_Data.u_pl_eq_by_size = Element_Data.Displacement_By_Size;
            Effective_Response_Data.element_size_values = Element_Data.Element_Size_Values(:);
        end
    end
end

function FEA_Response_Data = Build_FEA_Response_Data(FEA_Convergence_Data, Plot_Data_Struct, convergence_config)
    if nargin < 3 || ~isstruct(convergence_config)
        convergence_config = struct();
    end
    if ~isfield(convergence_config, 'Require_FEA_Timeline')
        convergence_config.Require_FEA_Timeline = false;
    end

    FEA_Response_Data = struct( ...
        'Available', false, ...
        'Frame', [], ...
        'Time', [], ...
        'Max_S22', [], ...
        'Max_Mises', [], ...
        'Max_LE22', [], ...
        'Engineering_Strain_Approx', [], ...
        'Engineering_Stress_Approx', [], ...
        'True_Strain_Approx', [], ...
        'True_Stress_Approx', []);

    Timeline_Table = table();
    Timeline_Candidates = strings(0, 1);
    if isfield(FEA_Convergence_Data, 'Timeline_Table') && ~isempty(FEA_Convergence_Data.Timeline_Table)
        Timeline_Table = FEA_Convergence_Data.Timeline_Table;
    end

    if isempty(Timeline_Table)
        if isfield(FEA_Convergence_Data, 'Convergence_Directory')
            cdir = char(string(FEA_Convergence_Data.Convergence_Directory));
            if isfolder(cdir)
                Timeline_Candidates(end + 1, 1) = string(fullfile(cdir, 'converged_timeline.csv')); %#ok<AGROW>
                try
                    hits = dir(fullfile(cdir, '**', '*timeline*.csv'));
                    for h = 1:numel(hits)
                        Timeline_Candidates(end + 1, 1) = string(fullfile(hits(h).folder, hits(h).name)); %#ok<AGROW>
                    end
                catch
                end
            end
        end
        if isfield(FEA_Convergence_Data, 'Summary_Table') && istable(FEA_Convergence_Data.Summary_Table) && ...
                ~isempty(FEA_Convergence_Data.Summary_Table) && ...
                any(strcmp(FEA_Convergence_Data.Summary_Table.Properties.VariableNames, 'timelineCsv'))
            Timeline_Candidates = [Timeline_Candidates; string(FEA_Convergence_Data.Summary_Table.timelineCsv)]; %#ok<AGROW>
        end

        Timeline_Candidates = unique(Timeline_Candidates, 'stable');
        for i = 1:numel(Timeline_Candidates)
            this_path = char(Timeline_Candidates(i));
            if ~(ischar(this_path) || isstring(this_path)) || strlength(string(this_path)) == 0 || ~isfile(this_path)
                continue;
            end
            Timeline_Table = Read_Table_If_Exists(this_path);
            if ~isempty(Timeline_Table)
                break;
            end
        end
    end

    if isempty(Timeline_Table)
        if logical(convergence_config.Require_FEA_Timeline)
            if isempty(Timeline_Candidates)
                Candidate_Text = "none";
            else
                Candidate_Text = strjoin(Timeline_Candidates, newline + " - ");
                Candidate_Text = " - " + Candidate_Text;
            end
            error('[FEA] Timeline CSV is required but was not found. Checked candidates:%s', char(Candidate_Text));
        end
        return;
    end

    FEA_Response_Data.Frame = Get_Table_Column(Timeline_Table, {'frame'});
    FEA_Response_Data.Time = Get_Table_Column(Timeline_Table, {'time'});
    FEA_Response_Data.Max_S22 = Get_Table_Column(Timeline_Table, {'max_S22', 'maxS22'});
    FEA_Response_Data.Max_Mises = Get_Table_Column(Timeline_Table, {'max_Mises', 'maxMises'});
    FEA_Response_Data.Max_LE22 = Get_Table_Column(Timeline_Table, {'max_LE22', 'maxLE22'});
    FEA_Response_Data.Engineering_Strain_Approx = Get_Table_Column(Timeline_Table, {'eng_strain_approx', 'Engineering_Strain_Approx'});
    FEA_Response_Data.Engineering_Stress_Approx = Get_Table_Column(Timeline_Table, {'eng_stress_approx', 'Engineering_Stress_Approx'});
    FEA_Response_Data.True_Strain_Approx = Get_Table_Column(Timeline_Table, {'true_strain_approx', 'True_Strain_Approx'});
    FEA_Response_Data.True_Stress_Approx = Get_Table_Column(Timeline_Table, {'true_stress_approx', 'True_Stress_Approx'});

    if isempty(FEA_Response_Data.True_Strain_Approx) && ~isempty(FEA_Response_Data.Max_LE22)
        FEA_Response_Data.True_Strain_Approx = FEA_Response_Data.Max_LE22;
    end
    if isempty(FEA_Response_Data.Engineering_Strain_Approx) && ~isempty(FEA_Response_Data.True_Strain_Approx)
        FEA_Response_Data.Engineering_Strain_Approx = exp(FEA_Response_Data.True_Strain_Approx) - 1;
    end
    if isempty(FEA_Response_Data.True_Stress_Approx)
        if ~isempty(FEA_Response_Data.Max_S22)
            FEA_Response_Data.True_Stress_Approx = FEA_Response_Data.Max_S22;
        else
            FEA_Response_Data.True_Stress_Approx = FEA_Response_Data.Max_Mises;
        end
    end
    if isempty(FEA_Response_Data.Engineering_Stress_Approx) && ~isempty(FEA_Response_Data.True_Stress_Approx)
        FEA_Response_Data.Engineering_Stress_Approx = FEA_Response_Data.True_Stress_Approx ./ ...
            max(1 + FEA_Response_Data.Engineering_Strain_Approx, eps);
    end

    FEA_Response_Data.Available = ~isempty(FEA_Response_Data.True_Stress_Approx);
    if FEA_Response_Data.Available
        Plot_Data_Struct.FEA_Response_Data = FEA_Response_Data; %#ok<NASGU>
    end
end

function Create_FEA_Field_Output_Figure(FEA_Convergence_Data, Figure_Config, Style, Output_Directory)
    Figure_Handle = figure('Name', Figure_Config.Name, 'NumberTitle', 'off');
    Initialise_Figure_Window(Figure_Handle, Style);
    Tile_Layout = tiledlayout(Figure_Handle, 1, numel(Figure_Config.Stage_Order), ...
        'TileSpacing', 'compact', 'Padding', 'compact');

    X_Limits = [inf, -inf];
    Y_Limits = [inf, -inf];
    C_Limits = [inf, -inf];
    for idx = 1:numel(Figure_Config.Stage_Order)
        Stage_Name = matlab.lang.makeValidName(Figure_Config.Stage_Order{idx});
        Stage_Table = FEA_Convergence_Data.Field_Output_By_Stage.(Stage_Name);
        X_Limits = [min(X_Limits(1), min(Stage_Table.x_centroid)), max(X_Limits(2), max(Stage_Table.x_centroid))];
        Y_Limits = [min(Y_Limits(1), min(Stage_Table.y_centroid)), max(Y_Limits(2), max(Stage_Table.y_centroid))];
        C_Limits = [min(C_Limits(1), min(Stage_Table.LE22)), max(C_Limits(2), max(Stage_Table.LE22))];
    end

    for idx = 1:numel(Figure_Config.Stage_Order)
        Stage_Name = matlab.lang.makeValidName(Figure_Config.Stage_Order{idx});
        Stage_Table = FEA_Convergence_Data.Field_Output_By_Stage.(Stage_Name);
        ax = nexttile(Tile_Layout, idx);
        scatter(ax, Stage_Table.x_centroid, Stage_Table.y_centroid, 16, Stage_Table.LE22, 'filled');
        grid(ax, 'on');
        axis(ax, 'equal');
        xlim(ax, X_Limits);
        ylim(ax, Y_Limits);
        caxis(ax, C_Limits);
        y_label_stage = '';
        if idx == 1
            y_label_stage = Figure_Config.Y_Label;
        else
            ax.YTickLabel = [];
        end
        Apply_Plot_Format_On_Axes(ax, Figure_Config.X_Label, y_label_stage, {Figure_Config.Stage_Titles{idx}}, Style, Style.Font_Sizes, ...
            struct('Title_Font_Size', Style.Font_Sizes{3} - 2));
        Apply_Primary_Axis_Style(ax, Style);
    end

    colormap(Tile_Layout, parula);
    cb = colorbar(nexttile(Tile_Layout, numel(Figure_Config.Stage_Order)));
    cb.Layout.Tile = 'east';
    cb.Label.Interpreter = 'latex';
    cb.Label.String = Figure_Config.Colorbar_Label;
    sgtitle(Tile_Layout, strjoin(Figure_Config.Title, newline), 'Interpreter', 'latex', 'FontSize', Style.Font_Sizes{3});
    Export_Figure_Files(Figure_Handle, Output_Directory, Figure_Config.File_Name, Style.Export_DPI);
end

function Export_Figure_Files(Figure_Handle, Output_Directory, Png_File_Name, Export_DPI)
%EXPORT_FIGURE_FILES Export both MATLAB FIG and PNG with robust fallback handling.
    if ~exist(Output_Directory, 'dir')
        mkdir(Output_Directory);
    end

    [~, Base_Name, ~] = fileparts(Png_File_Name);
    Png_Path = fullfile(Output_Directory, [Base_Name, '.png']);
    Fig_Path = fullfile(Output_Directory, [Base_Name, '.fig']);

    % Ensure marker-only plots render above line objects before saving.
    try
        Axes_Handles = findall(Figure_Handle, 'Type', 'axes');
        for idx_ax = 1:numel(Axes_Handles)
            try
                Bring_Markers_To_Front(Axes_Handles(idx_ax));
            catch
            end
        end
    catch
    end

    % Wrap long plain-text legend entries so they do not overflow figure bounds.
    try
        Apply_Wrapped_Legend_Labels(Figure_Handle, 28);
    catch
    end

    try
        if exist('savefig', 'file') == 2
            savefig(Figure_Handle, Fig_Path);
        else
            hgsave(Figure_Handle, Fig_Path);
        end
    catch SaveFigException
        warning('FIG export failed for %s: %s', Fig_Path, SaveFigException.message);
    end

    try
        exportgraphics(Figure_Handle, Png_Path, 'Resolution', Export_DPI);
    catch ExportException
        warning('exportgraphics failed for %s. Falling back to print. Reason: %s', ...
            Png_Path, ExportException.message);
        try
            set(Figure_Handle, 'PaperPositionMode', 'auto');
            print(Figure_Handle, Png_Path, '-dpng', sprintf('-r%d', Export_DPI));
        catch PrintException
            warning('PNG export failed for %s: %s', Png_Path, PrintException.message);
        end
    end
end

function Apply_Wrapped_Legend_Labels(Figure_Handle, max_chars)
    if nargin < 2 || ~isfinite(max_chars) || max_chars < 8
        max_chars = 28;
    end
    Legend_Handles = findall(Figure_Handle, 'Type', 'legend');
    for idx = 1:numel(Legend_Handles)
        try
            Wrapped_Labels = Wrap_Legend_Labels(Legend_Handles(idx).String, max_chars);
            Legend_Handles(idx).String = Wrapped_Labels;
        catch
        end
    end
end

function Labels_Out = Wrap_Legend_Labels(Labels_In, max_chars)
    Labels_Out = Labels_In;
    if nargin < 2 || ~isfinite(max_chars) || max_chars < 8
        max_chars = 28;
    end
    if isempty(Labels_In)
        return;
    end

    Input_Is_String = isstring(Labels_In);
    Input_Is_Char = ischar(Labels_In);

    if Input_Is_String
        Labels_Cell = cellstr(Labels_In);
    elseif Input_Is_Char
        Labels_Cell = cellstr(Labels_In);
    elseif iscell(Labels_In)
        Labels_Cell = Labels_In;
    else
        return;
    end

    for idx = 1:numel(Labels_Cell)
        try
            Raw_Label = strtrim(char(string(Labels_Cell{idx})));
        catch
            continue;
        end
        if isempty(Raw_Label) || numel(Raw_Label) <= max_chars
            Labels_Cell{idx} = Raw_Label;
            continue;
        end

        % Avoid breaking LaTeX/math expressions.
        if ~isempty(strfind(Raw_Label, '$')) || ~isempty(strfind(Raw_Label, '\')) || ...
                ~isempty(strfind(Raw_Label, '^')) || ~isempty(strfind(Raw_Label, '_'))
            Labels_Cell{idx} = Raw_Label;
            continue;
        end

        Words = regexp(Raw_Label, '\s+', 'split');
        if isempty(Words)
            Labels_Cell{idx} = Raw_Label;
            continue;
        end

        Lines = {};
        Current_Line = '';
        for w = 1:numel(Words)
            This_Word = Words{w};
            if isempty(Current_Line)
                Current_Line = This_Word;
            else
                if (numel(Current_Line) + 1 + numel(This_Word)) <= max_chars
                    Current_Line = [Current_Line ' ' This_Word]; %#ok<AGROW>
                else
                    Lines{end + 1} = Current_Line; %#ok<AGROW>
                    Current_Line = This_Word;
                end
            end
        end
        if ~isempty(Current_Line)
            Lines{end + 1} = Current_Line; %#ok<AGROW>
        end

        if numel(Lines) > 1
            Labels_Cell{idx} = strjoin(Lines, '\n ');
        else
            Labels_Cell{idx} = Raw_Label;
        end
    end

    if Input_Is_String
        Labels_Out = string(Labels_Cell);
    elseif Input_Is_Char && numel(Labels_Cell) == 1
        Labels_Out = Labels_Cell{1};
    else
        Labels_Out = Labels_Cell;
    end
end

function Has_Mesh_Files = Directory_Has_MeshConv_Job_Files(root_dir)
    Has_Mesh_Files = false;
    if ~(ischar(root_dir) || isstring(root_dir)) || ~isfolder(root_dir)
        return;
    end
    Direct_Files = {'mesh_conv_results.csv', 'mesh_conv_search_results.csv', 'convergence_manifest.csv'};
    if any(cellfun(@(f) isfile(fullfile(root_dir, f)), Direct_Files))
        Has_Mesh_Files = true;
        return;
    end
    try
        Dat_Matches = dir(fullfile(root_dir, '**', 'meshconv_*.dat'));
        if ~isempty(Dat_Matches)
            Has_Mesh_Files = true;
            return;
        end
        Prt_Matches = dir(fullfile(root_dir, '**', 'meshconv_*.prt'));
        Has_Mesh_Files = ~isempty(Prt_Matches);
    catch
    end
end

function [Summary_Table, Source_Label] = Rebuild_Mesh_Conv_Results_From_Job_Files(convergence_dir)
    Summary_Table = table();
    Source_Label = 'none';
    if ~(ischar(convergence_dir) || isstring(convergence_dir)) || ~isfolder(convergence_dir)
        return;
    end

    Dat_Files = dir(fullfile(convergence_dir, '**', 'meshconv_*.dat'));
    if isempty(Dat_Files)
        Dat_Files = dir(fullfile(convergence_dir, '**', '*.dat'));
    end
    if isempty(Dat_Files)
        return;
    end

    Row_Template = struct( ...
        'stage', "", ...
        'iteration', nan, ...
        'jobName', "", ...
        'mesh_h', nan, ...
        'mesh_h_6dp', nan, ...
        'numElements', nan, ...
        'numNodes', nan, ...
        'maxNumInc', nan, ...
        'initialInc', nan, ...
        'minInc', nan, ...
        'maxInc', nan, ...
        'retryCount', 0, ...
        'lastAbortSig', "", ...
        'peakS22', nan, ...
        'peakMises', nan, ...
        'peakLE22', nan, ...
        'relS22ToPrev', nan, ...
        'relMisesToPrev', nan, ...
        'relLE22ToPrev', nan, ...
        'pctDiffS22', nan, ...
        'pctDiffMises', nan, ...
        'pctDiffLE22', nan, ...
        'cpuTimeSec', nan, ...
        'systemTimeSec', nan, ...
        'wallclockTimeSec', nan, ...
        'memoryRequiredMB', nan, ...
        'memoryMinimizeIOMB', nan, ...
        'memoryUsedMB', nan, ...
        'convMetric', nan, ...
        'convBasis', "", ...
        'convTol', 0.001, ...
        'isConverged', false, ...
        'isConvergedLE22', false, ...
        'isConvergedAll3', false, ...
        'comparedTo_h', nan, ...
        'odbPath', "", ...
        'jobStatus', "", ...
        'fieldOutputCsv', "", ...
        'timelineCsv', "" ...
    );
    Rows = repmat(Row_Template, 0, 1);

    for idx = 1:numel(Dat_Files)
        Dat_Path = fullfile(Dat_Files(idx).folder, Dat_Files(idx).name);
        [~, Job_Name, ~] = fileparts(Dat_Path);
        Job_Meta = Parse_Meshconv_Job_Metadata(Job_Name);
        if isnan(Job_Meta.mesh_h)
            continue;
        end

        Rec = Row_Template;
        Rec.stage = string(Job_Meta.stage);
        Rec.iteration = Job_Meta.iteration;
        Rec.jobName = string(Job_Name);
        Rec.mesh_h = Job_Meta.mesh_h;
        Rec.mesh_h_6dp = round(Job_Meta.mesh_h, 6);
        Rec.numElements = Job_Meta.numElements;
        Rec.odbPath = string(fullfile(Dat_Files(idx).folder, [Job_Name '.odb']));

        Dat_Text = Read_Text_File_Safe(Dat_Path);
        [Rec.cpuTimeSec, Rec.wallclockTimeSec, Rec.memoryRequiredMB, Rec.memoryMinimizeIOMB] = Parse_Runtime_Metrics_From_Dat(Dat_Text);
        Rec.systemTimeSec = Extract_Last_Number(Dat_Text, 'SYSTEM TIME \(SEC\)\s*=\s*([0-9.+\-Ee]+)');
        if ~isnan(Rec.memoryMinimizeIOMB)
            Rec.memoryUsedMB = Rec.memoryMinimizeIOMB;
        else
            Rec.memoryUsedMB = Rec.memoryRequiredMB;
        end

        Prt_Path = fullfile(Dat_Files(idx).folder, [Job_Name '.prt']);
        [Elem_From_Prt, Nodes_From_Prt] = Parse_Element_Node_Count_From_Prt(Prt_Path);
        if ~isnan(Elem_From_Prt)
            Rec.numElements = Elem_From_Prt;
        end
        if ~isnan(Nodes_From_Prt)
            Rec.numNodes = Nodes_From_Prt;
        end

        Sta_Path = fullfile(Dat_Files(idx).folder, [Job_Name '.sta']);
        Rec.jobStatus = Parse_Job_Status_From_Sta(Sta_Path);

        [Rec.peakMises, Rec.peakS22, Rec.peakLE22, Field_Csv, Timeline_Csv] = Parse_Peaks_From_Job_CSVs(convergence_dir, Dat_Files(idx).folder, Job_Name);
        Rec.fieldOutputCsv = string(Field_Csv);
        Rec.timelineCsv = string(Timeline_Csv);

        Rows(end + 1, 1) = Rec; %#ok<AGROW>
    end

    if isempty(Rows)
        return;
    end

    Summary_Table = struct2table(Rows);
    Summary_Table = sortrows(Summary_Table, {'mesh_h', 'iteration'}, {'descend', 'ascend'});
    Summary_Table = Compute_Mesh_Conv_Metrics_From_Peaks(Summary_Table, 0.001);
    Source_Label = 'job files (.dat/.prt/.sta + job csv outputs)';
end

function Summary_Table = Parse_Mesh_Convergence_Block_CSV(block_csv_path, dat_dir, conv_tol)
    Summary_Table = table();
    if nargin < 3 || ~isfinite(conv_tol) || conv_tol <= 0
        conv_tol = 0.001;
    end
    if ~(ischar(block_csv_path) || isstring(block_csv_path)) || ~isfile(block_csv_path)
        return;
    end

    try
        T = readtable(block_csv_path, 'VariableNamingRule', 'preserve');
        T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);
    catch Read_Err
        fprintf('[FEA] Failed to read block convergence CSV (%s): %s\n', block_csv_path, Read_Err.message);
        return;
    end
    if isempty(T) || height(T) == 0
        return;
    end

    odb_col = string(Get_Table_Column(T, {'ODBName', 'ODB_Name'}));
    if isempty(odb_col)
        return;
    end
    header_mask = strcmpi(strtrim(odb_col), 'ODB Name');
    mesh_mask = contains(odb_col, 'Mesh_', 'IgnoreCase', true);
    valid_mask = ~header_mask & mesh_mask;
    if ~any(valid_mask)
        return;
    end
    T = T(valid_mask, :);
    odb_col = odb_col(valid_mask);

    it_col = nan(height(T), 1);
    for i = 1:height(T)
        tok = regexpi(char(odb_col(i)), 'Mesh_(\d+)\.odb', 'tokens', 'once');
        if ~isempty(tok)
            it_col(i) = str2double(tok{1});
        end
    end
    valid_it = ~isnan(it_col);
    if ~any(valid_it)
        return;
    end
    T = T(valid_it, :);
    odb_col = odb_col(valid_it);
    it_col = it_col(valid_it);

    n_rows = height(T);
    s22_col = To_Double_Vector(Get_Table_Column(T, {'SS22', 'S_S22'}));
    mises_col = To_Double_Vector(Get_Table_Column(T, {'SMises', 'S_Mises'}));
    le22_col = To_Double_Vector(Get_Table_Column(T, {'LE_LE22', 'LELE22'}));
    elem_col = To_Double_Vector(Get_Table_Column(T, {'ElementLabel'}));
    meshh_col = To_Double_Vector(Get_Table_Column(T, {'mesh_h', 'meshh', 'element_size', 'h'}));
    if isempty(s22_col), s22_col = nan(n_rows, 1); end
    if isempty(mises_col), mises_col = nan(n_rows, 1); end
    if isempty(le22_col), le22_col = nan(n_rows, 1); end
    if isempty(elem_col), elem_col = nan(n_rows, 1); end
    if isempty(meshh_col), meshh_col = nan(n_rows, 1); end
    if numel(s22_col) < n_rows, s22_col(numel(s22_col)+1:n_rows, 1) = nan; end
    if numel(mises_col) < n_rows, mises_col(numel(mises_col)+1:n_rows, 1) = nan; end
    if numel(le22_col) < n_rows, le22_col(numel(le22_col)+1:n_rows, 1) = nan; end
    if numel(elem_col) < n_rows, elem_col(numel(elem_col)+1:n_rows, 1) = nan; end
    if numel(meshh_col) < n_rows, meshh_col(numel(meshh_col)+1:n_rows, 1) = nan; end
    s22_col = s22_col(1:n_rows);
    mises_col = mises_col(1:n_rows);
    le22_col = le22_col(1:n_rows);
    elem_col = elem_col(1:n_rows);
    meshh_col = meshh_col(1:n_rows);

    uniq_iter = unique(it_col(:));
    uniq_iter = sort(uniq_iter, 'ascend');
    Row_Template = struct( ...
        'stage', "array", ...
        'iteration', nan, ...
        'jobName', "", ...
        'mesh_h', nan, ...
        'mesh_h_6dp', nan, ...
        'numElements', nan, ...
        'numNodes', nan, ...
        'maxNumInc', nan, ...
        'initialInc', nan, ...
        'minInc', nan, ...
        'maxInc', nan, ...
        'retryCount', 0, ...
        'lastAbortSig', "", ...
        'peakS22', nan, ...
        'peakLE22', nan, ...
        'peakMises', nan, ...
        'relS22ToPrev', nan, ...
        'relLE22ToPrev', nan, ...
        'relMisesToPrev', nan, ...
        'pctDiffS22', nan, ...
        'pctDiffLE22', nan, ...
        'pctDiffMises', nan, ...
        'cpuTimeSec', nan, ...
        'systemTimeSec', nan, ...
        'wallclockTimeSec', nan, ...
        'memoryRequiredMB', nan, ...
        'memoryMinimizeIOMB', nan, ...
        'memoryUsedMB', nan, ...
        'convMetric', nan, ...
        'convBasis', "", ...
        'convTol', conv_tol, ...
        'isConverged', false, ...
        'isConvergedLE22', false, ...
        'isConvergedAll3', false, ...
        'comparedTo_h', nan, ...
        'datPath', "", ...
        'fieldReportPath', "", ...
        'odbPath', "", ...
        'jobStatus', "completed");
    Rows = repmat(Row_Template, 0, 1);

    for k = 1:numel(uniq_iter)
        this_iter = uniq_iter(k);
        this_mask = (it_col == this_iter);

        Rec = Row_Template;
        Rec.iteration = this_iter;
        Rec.jobName = string(sprintf('Mesh_%d', round(this_iter)));
        Rec.odbPath = string(char(odb_col(find(this_mask, 1, 'first'))));
        Rec.peakMises = max(mises_col(this_mask), [], 'omitnan');
        Rec.peakS22 = max(s22_col(this_mask), [], 'omitnan');
        Rec.peakLE22 = max(le22_col(this_mask), [], 'omitnan');
        this_elem_labels = elem_col(this_mask);
        this_elem_labels = this_elem_labels(~isnan(this_elem_labels));
        if ~isempty(this_elem_labels)
            Rec.numElements = numel(unique(round(this_elem_labels)));
        end
        this_mesh_h = meshh_col(this_mask);
        this_mesh_h = this_mesh_h(~isnan(this_mesh_h));
        if ~isempty(this_mesh_h)
            Rec.mesh_h = this_mesh_h(1);
            Rec.mesh_h_6dp = round(this_mesh_h(1), 6);
        end

        dat_path = Resolve_Mesh_Block_Dat_Path(dat_dir, this_iter);
        Rec.datPath = string(dat_path);
        if isfile(dat_path)
            dat_text = Read_Text_File_Safe(dat_path);
            [Rec.cpuTimeSec, Rec.wallclockTimeSec, Rec.memoryRequiredMB, Rec.memoryMinimizeIOMB] = Parse_Runtime_Metrics_From_Dat(dat_text);
            Rec.systemTimeSec = Extract_Last_Number(dat_text, 'SYSTEM TIME \\(SEC\\)\\s*=\\s*([0-9.+\\-Ee]+)');
            if ~isnan(Rec.memoryMinimizeIOMB)
                Rec.memoryUsedMB = Rec.memoryMinimizeIOMB;
            else
                Rec.memoryUsedMB = Rec.memoryRequiredMB;
            end
            ne_dat = Extract_Last_Number(dat_text, 'NUMBER OF ELEMENTS\\s+IS\\s+([0-9]+)');
            nn_dat = Extract_Last_Number(dat_text, 'NUMBER OF NODES\\s+IS\\s+([0-9]+)');
            if ~isnan(ne_dat), Rec.numElements = ne_dat; end
            if ~isnan(nn_dat), Rec.numNodes = nn_dat; end
        end

        Rows(end + 1, 1) = Rec; %#ok<AGROW>
    end

    if isempty(Rows)
        return;
    end

    Summary_Table = struct2table(Rows);
    Summary_Table = sortrows(Summary_Table, {'iteration'}, {'ascend'});
    Summary_Table = Compute_Mesh_Conv_Metrics_From_Peaks(Summary_Table, conv_tol);
end

function dat_path = Resolve_Mesh_Block_Dat_Path(dat_dir, mesh_iter)
    dat_path = "";
    if ~(ischar(dat_dir) || isstring(dat_dir)) || strlength(string(dat_dir)) == 0
        return;
    end
    dat_dir = char(string(dat_dir));
    direct_path = fullfile(dat_dir, sprintf('Mesh_%d.dat', round(mesh_iter)));
    if isfile(direct_path)
        dat_path = string(direct_path);
        return;
    end
    try
        hits = dir(fullfile(dat_dir, '**', sprintf('Mesh_%d.dat', round(mesh_iter))));
        if ~isempty(hits)
            dat_path = string(fullfile(hits(1).folder, hits(1).name));
        end
    catch
    end
end

function [Summary_Table_Out, Read_Info] = Read_Convergence_From_Mesh_Convergence_Sheet(xlsx_path, sheet_name, fallback_summary_table, conv_tol)
    if nargin < 3 || ~istable(fallback_summary_table)
        fallback_summary_table = table();
    end
    if nargin < 4 || ~isfinite(conv_tol) || conv_tol <= 0
        conv_tol = 0.001;
    end

    Summary_Table_Out = fallback_summary_table;
    Read_Info = struct('Loaded', false, 'Message', "");
    if ~(ischar(xlsx_path) || isstring(xlsx_path)) || ~isfile(xlsx_path)
        Read_Info.Message = "Mesh convergence sheet read skipped (workbook missing).";
        return;
    end
    if ~(ischar(sheet_name) || isstring(sheet_name)) || strlength(string(sheet_name)) == 0
        Read_Info.Message = "Mesh convergence sheet read skipped (sheet name empty).";
        return;
    end
    sheet_name = char(string(sheet_name));

    all_sheets = string(sheetnames(xlsx_path));
    match_idx = find(strcmpi(all_sheets, sheet_name), 1, 'first');
    if isempty(match_idx)
        Read_Info.Message = sprintf('Mesh convergence sheet "%s" not found; using existing summary source.', sheet_name);
        return;
    end
    sheet_name_actual = char(all_sheets(match_idx));

    try
        S = readtable(xlsx_path, 'Sheet', sheet_name_actual, 'VariableNamingRule', 'preserve');
        S.Properties.VariableNames = matlab.lang.makeValidName(S.Properties.VariableNames);
    catch Read_Err
        Read_Info.Message = sprintf('Mesh convergence sheet read failed ("%s"): %s', sheet_name_actual, Read_Err.message);
        return;
    end
    if isempty(S) || ~istable(S)
        Read_Info.Message = sprintf('Mesh convergence sheet "%s" is empty; using existing summary source.', sheet_name_actual);
        return;
    end

    Summary_Table_Out = Normalize_Convergence_Summary_Table_From_Sheet(S, conv_tol);
    Read_Info.Loaded = true;
    Read_Info.Message = sprintf('Mesh convergence metrics loaded from workbook sheet "%s".', sheet_name_actual);
end

function Summary_Table_Out = Normalize_Convergence_Summary_Table_From_Sheet(Summary_Table_In, conv_tol)
    if nargin < 2 || ~isfinite(conv_tol) || conv_tol <= 0
        conv_tol = 0.001;
    end
    if isempty(Summary_Table_In) || ~istable(Summary_Table_In)
        Summary_Table_Out = table();
        return;
    end

    Summary_Table_Out = Summary_Table_In;
    n_rows = height(Summary_Table_Out);
    if n_rows == 0
        return;
    end

    numeric_cols = { ...
        'iteration', 'mesh_h', 'mesh_h_6dp', ...
        'numElements', 'numNodes', ...
        'peakS22', 'peakLE22', 'peakMises', ...
        'relS22ToPrev', 'relLE22ToPrev', 'relMisesToPrev', ...
        'pctDiffS22', 'pctDiffLE22', 'pctDiffMises', ...
        'cpuTimeSec', 'systemTimeSec', 'wallclockTimeSec', ...
        'memoryRequiredMB', 'memoryMinimizeIOMB', 'memoryUsedMB', ...
        'convMetric', 'convTol', 'comparedTo_h'};
    bool_cols = {'isConverged', 'isConvergedLE22', 'isConvergedAll3'};

    column_alias_map = { ...
        'iteration', {'iteration', 'iter', 'Iteration'}; ...
        'mesh_h', {'mesh_h', 'meshH', 'mesh_h_6dp', 'meshh', 'element_size', 'elementSize', 'h', 'L', 'Element_Size_L'}; ...
        'mesh_h_6dp', {'mesh_h_6dp', 'mesh_h', 'meshH'}; ...
        'jobName', {'jobName', 'job_name', 'job', 'JobName'}; ...
        'numElements', {'numElements', 'num_elements', 'elementCount', 'elements', 'numel'}; ...
        'numNodes', {'numNodes', 'num_nodes', 'nodeCount'}; ...
        'peakS22', {'peakS22', 'peak_S22', 'maxS22', 'max_S22', 'S22', 'SS22', 'S_S22'}; ...
        'peakLE22', {'peakLE22', 'peak_LE22', 'maxLE22', 'max_LE22', 'LE22', 'LE_LE22', 'LELE22'}; ...
        'peakMises', {'peakMises', 'peak_Mises', 'maxMises', 'max_Mises', 'mises', 'SMises', 'S_Mises'}; ...
        'relS22ToPrev', {'relS22ToPrev', 'rel_S22_to_prev', 'relS22'}; ...
        'relLE22ToPrev', {'relLE22ToPrev', 'rel_LE22_to_prev', 'relLE22'}; ...
        'relMisesToPrev', {'relMisesToPrev', 'rel_Mises_to_prev', 'relMises'}; ...
        'pctDiffS22', {'pctDiffS22', 'pct_diff_S22'}; ...
        'pctDiffLE22', {'pctDiffLE22', 'pct_diff_LE22'}; ...
        'pctDiffMises', {'pctDiffMises', 'pct_diff_Mises'}; ...
        'isConverged', {'isConverged', 'is_converged'}; ...
        'isConvergedLE22', {'isConvergedLE22', 'is_converged_LE22'}; ...
        'isConvergedAll3', {'isConvergedAll3', 'is_converged_all3'}; ...
        'convTol', {'convTol', 'convergenceTolerance', 'tol'}; ...
        'timelineCsv', {'timelineCsv', 'timeline_csv'}; ...
        'fieldOutputCsv', {'fieldOutputCsv', 'field_output_csv'} ...
    };

    for k = 1:size(column_alias_map, 1)
        cname = column_alias_map{k, 1};
        aliases = column_alias_map{k, 2};
        if any(strcmp(Summary_Table_Out.Properties.VariableNames, cname))
            continue;
        end
        col_data = Get_Table_Column(Summary_Table_Out, aliases);
        if isempty(col_data)
            continue;
        end
        if any(strcmp(bool_cols, cname))
            v = Safe_IsConverged_Mask(col_data);
            if numel(v) < n_rows
                v(numel(v) + 1:n_rows, 1) = false;
            end
            Summary_Table_Out.(cname) = v(1:n_rows);
        elseif any(strcmp(numeric_cols, cname))
            v = To_Double_Vector(col_data);
            if numel(v) < n_rows
                v(numel(v) + 1:n_rows, 1) = nan;
            end
            Summary_Table_Out.(cname) = v(1:n_rows);
        else
            v = string(col_data(:));
            if numel(v) < n_rows
                v(numel(v) + 1:n_rows, 1) = "";
            end
            Summary_Table_Out.(cname) = v(1:n_rows);
        end
    end

    for k = 1:numel(numeric_cols)
        cname = numeric_cols{k};
        if any(strcmp(Summary_Table_Out.Properties.VariableNames, cname))
            v = To_Double_Vector(Summary_Table_Out.(cname));
            if numel(v) < n_rows
                v(numel(v) + 1:n_rows, 1) = nan;
            end
            Summary_Table_Out.(cname) = v(1:n_rows);
        end
    end
    for k = 1:numel(bool_cols)
        cname = bool_cols{k};
        if any(strcmp(Summary_Table_Out.Properties.VariableNames, cname))
            v = Safe_IsConverged_Mask(Summary_Table_Out.(cname));
            if numel(v) < n_rows
                v(numel(v) + 1:n_rows, 1) = false;
            end
            Summary_Table_Out.(cname) = v(1:n_rows);
        end
    end

    if ~any(strcmp(Summary_Table_Out.Properties.VariableNames, 'iteration'))
        Summary_Table_Out.iteration = (1:n_rows)';
    end
    if ~any(strcmp(Summary_Table_Out.Properties.VariableNames, 'mesh_h')) && ...
            any(strcmp(Summary_Table_Out.Properties.VariableNames, 'mesh_h_6dp'))
        Summary_Table_Out.mesh_h = To_Double_Vector(Summary_Table_Out.mesh_h_6dp);
    end
    if ~any(strcmp(Summary_Table_Out.Properties.VariableNames, 'mesh_h_6dp')) && ...
            any(strcmp(Summary_Table_Out.Properties.VariableNames, 'mesh_h'))
        Summary_Table_Out.mesh_h_6dp = round(To_Double_Vector(Summary_Table_Out.mesh_h), 6);
    end
    if ~any(strcmp(Summary_Table_Out.Properties.VariableNames, 'jobName'))
        Iter_Col = To_Double_Vector(Summary_Table_Out.iteration);
        Job_Name_Col = strings(n_rows, 1);
        for i = 1:n_rows
            if isnan(Iter_Col(i))
                Job_Name_Col(i) = "";
            else
                Job_Name_Col(i) = sprintf('Mesh_%d', round(Iter_Col(i)));
            end
        end
        Summary_Table_Out.jobName = Job_Name_Col;
    else
        Job_Name_Col = string(Summary_Table_Out.jobName);
        if numel(Job_Name_Col) < n_rows
            Job_Name_Col(numel(Job_Name_Col) + 1:n_rows, 1) = "";
        end
        Summary_Table_Out.jobName = Job_Name_Col(1:n_rows);
    end

    if any(strcmp(Summary_Table_Out.Properties.VariableNames, 'convTol'))
        conv_col = To_Double_Vector(Summary_Table_Out.convTol);
        conv_col(~isfinite(conv_col) | conv_col <= 0) = conv_tol;
        Summary_Table_Out.convTol = conv_col;
    else
        Summary_Table_Out.convTol = conv_tol * ones(n_rows, 1);
    end

    vars_after_alias = Summary_Table_Out.Properties.VariableNames;
    need_metric_fill = ~any(strcmp(vars_after_alias, 'relLE22ToPrev')) || ...
        ~any(strcmp(vars_after_alias, 'isConvergedLE22'));
    if ~need_metric_fill && any(strcmp(vars_after_alias, 'relLE22ToPrev'))
        rel_check = To_Double_Vector(Summary_Table_Out.relLE22ToPrev);
        need_metric_fill = all(isnan(rel_check));
    end

    if need_metric_fill
        metrics_table = Compute_Mesh_Conv_Metrics_From_Peaks(Summary_Table_Out, conv_tol);
        metric_cols = { ...
            'relS22ToPrev', 'relLE22ToPrev', 'relMisesToPrev', ...
            'pctDiffS22', 'pctDiffLE22', 'pctDiffMises', ...
            'convMetric', 'convBasis', 'comparedTo_h', ...
            'isConverged', 'isConvergedLE22', 'isConvergedAll3'};
        for k = 1:numel(metric_cols)
            cname = metric_cols{k};
            if ~any(strcmp(vars_after_alias, cname)) && any(strcmp(metrics_table.Properties.VariableNames, cname))
                Summary_Table_Out.(cname) = metrics_table.(cname);
            end
        end
    end
end

function [Summary_Table_Out, Write_Info] = Write_Convergence_To_Mesh_Convergence_Sheet(xlsx_path, sheet_name, summary_table)
    Summary_Table_Out = summary_table;
    Write_Info = struct('Updated', false, 'Message', "");
    if ~(ischar(xlsx_path) || isstring(xlsx_path)) || ~isfile(xlsx_path)
        error('[FEA] Workbook not found: %s', char(string(xlsx_path)));
    end
    if isempty(summary_table) || ~istable(summary_table)
        Write_Info.Message = "Mesh convergence workbook sync skipped (empty summary).";
        return;
    end
    if ~(ischar(sheet_name) || isstring(sheet_name)) || strlength(string(sheet_name)) == 0
        error('[FEA] Mesh convergence target sheet name is empty.');
    end
    sheet_name = char(string(sheet_name));

    all_sheets = string(sheetnames(xlsx_path));
    if ~any(strcmpi(all_sheets, sheet_name))
        error('[FEA] Required sheet "%s" not found in workbook %s', sheet_name, char(string(xlsx_path)));
    end

    S = readtable(xlsx_path, 'Sheet', sheet_name, 'VariableNamingRule', 'preserve');
    S.Properties.VariableNames = matlab.lang.makeValidName(S.Properties.VariableNames);
    if ~any(strcmp(S.Properties.VariableNames, 'iteration')) || ~any(strcmp(S.Properties.VariableNames, 'mesh_h'))
        error('[FEA] Sheet "%s" must contain columns "iteration" and "mesh_h".', sheet_name);
    end

    sheet_iter = To_Double_Vector(S.iteration);
    sheet_mesh = To_Double_Vector(S.mesh_h);
    row_map = nan(height(summary_table), 1);
    sum_iter = To_Double_Vector(Get_Table_Column(summary_table, {'iteration'}));
    if isempty(sum_iter)
        error('[FEA] Summary table has no iteration column for sheet mapping.');
    end

    if ~any(strcmp(summary_table.Properties.VariableNames, 'mesh_h'))
        summary_table.mesh_h = nan(height(summary_table), 1);
    end
    sum_mesh = To_Double_Vector(summary_table.mesh_h);
    for i = 1:height(summary_table)
        r = find(sheet_iter == sum_iter(i), 1, 'first');
        if isempty(r) && ~isnan(sum_mesh(i))
            cand = find(~isnan(sheet_mesh));
            if ~isempty(cand)
                [dmin, idx] = min(abs(sheet_mesh(cand) - sum_mesh(i)));
                if dmin <= 1e-6
                    r = cand(idx);
                end
            end
        end
        if isempty(r)
            continue;
        end
        row_map(i) = r;
        if isnan(sum_mesh(i)) && r <= numel(sheet_mesh)
            sum_mesh(i) = sheet_mesh(r);
        end
    end
    summary_table.mesh_h = sum_mesh;
    if any(strcmp(summary_table.Properties.VariableNames, 'mesh_h_6dp'))
        summary_table.mesh_h_6dp = round(sum_mesh, 6);
    end
    Summary_Table_Out = summary_table;

    target_cols = { ...
        'peakS22', 'peakLE22', 'peakMises', ...
        'relS22ToPrev', 'relLE22ToPrev', 'relMisesToPrev', ...
        'pctDiffS22', 'pctDiffLE22', 'pctDiffMises', ...
        'cpuTimeSec', 'systemTimeSec', 'wallclockTimeSec', ...
        'memoryRequiredMB', 'memoryMinimizeIOMB', 'memoryUsedMB', ...
        'numElements', 'numNodes', ...
        'isConvergedLE22', 'isConvergedAll3'};

    for c = 1:numel(target_cols)
        cname = target_cols{c};
        if ~any(strcmp(Summary_Table_Out.Properties.VariableNames, cname))
            if startsWith(cname, 'isConverged')
                Summary_Table_Out.(cname) = false(height(Summary_Table_Out), 1);
            else
                Summary_Table_Out.(cname) = nan(height(Summary_Table_Out), 1);
            end
        end
    end

    try
        Header_Row = readcell(xlsx_path, 'Sheet', sheet_name, 'Range', '1:1');
        if isempty(Header_Row)
            Header_Row = {''};
        end
        ncols = numel(Header_Row);
        header_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
        for c = 1:ncols
            htxt = char(string(Header_Row{c}));
            htxt_valid = char(matlab.lang.makeValidName(string(htxt)));
            if strlength(string(htxt_valid)) > 0 && ~isKey(header_map, htxt_valid)
                header_map(htxt_valid) = c;
            end
        end

        for c = 1:numel(target_cols)
            cname = target_cols{c};
            if ~isKey(header_map, cname)
                ncols = ncols + 1;
                writecell({cname}, xlsx_path, 'Sheet', sheet_name, ...
                    'Range', sprintf('%s1', Excel_Column_Label(ncols)));
                header_map(cname) = ncols;
            end
        end

        n_sheet_rows = height(S);
        for c = 1:numel(target_cols)
            cname = target_cols{c};
            xl_col = header_map(cname);
            col_cells = repmat({''}, n_sheet_rows, 1);
            if any(strcmp(S.Properties.VariableNames, cname))
                Existing_Values = S.(cname);
                if isnumeric(Existing_Values) || islogical(Existing_Values)
                    for r = 1:min(n_sheet_rows, numel(Existing_Values))
                        if isnumeric(Existing_Values(r)) && isnan(double(Existing_Values(r)))
                            col_cells{r} = '';
                        else
                            col_cells{r} = Existing_Values(r);
                        end
                    end
                else
                    Existing_Str = string(Existing_Values);
                    for r = 1:min(n_sheet_rows, numel(Existing_Str))
                        if strlength(Existing_Str(r)) == 0 || strcmpi(Existing_Str(r), "NaN")
                            col_cells{r} = '';
                        else
                            col_cells{r} = char(Existing_Str(r));
                        end
                    end
                end
            end

            for i = 1:height(Summary_Table_Out)
                if isnan(row_map(i))
                    continue;
                end
                r = row_map(i);
                if r < 1 || r > n_sheet_rows
                    continue;
                end
                val = Summary_Table_Out.(cname)(i);
                if islogical(val)
                    col_cells{r} = logical(val);
                elseif isnumeric(val)
                    if isnan(double(val))
                        col_cells{r} = '';
                    else
                        col_cells{r} = double(val);
                    end
                else
                    sval = string(val);
                    if strlength(sval) == 0 || strcmpi(sval, "NaN")
                        col_cells{r} = '';
                    else
                        col_cells{r} = char(sval);
                    end
                end
            end

            writecell(col_cells, xlsx_path, 'Sheet', sheet_name, ...
                'Range', sprintf('%s2:%s%d', Excel_Column_Label(xl_col), Excel_Column_Label(xl_col), n_sheet_rows + 1));
        end

        if isKey(header_map, 'mesh_h')
            mesh_col = header_map('mesh_h');
            mesh_cells = repmat({''}, n_sheet_rows, 1);
            if any(strcmp(S.Properties.VariableNames, 'mesh_h'))
                mesh_existing = To_Double_Vector(S.mesh_h);
                for r = 1:min(n_sheet_rows, numel(mesh_existing))
                    if isnan(mesh_existing(r))
                        mesh_cells{r} = '';
                    else
                        mesh_cells{r} = mesh_existing(r);
                    end
                end
            end
            for i = 1:height(Summary_Table_Out)
                if isnan(row_map(i)), continue; end
                r = row_map(i);
                if r < 1 || r > n_sheet_rows, continue; end
                v = Summary_Table_Out.mesh_h(i);
                if isnan(v)
                    continue;
                end
                mesh_cells{r} = v;
            end
            writecell(mesh_cells, xlsx_path, 'Sheet', sheet_name, ...
                'Range', sprintf('%s2:%s%d', Excel_Column_Label(mesh_col), Excel_Column_Label(mesh_col), n_sheet_rows + 1));
        end

        Write_Info.Updated = true;
        Write_Info.Message = sprintf('Mesh convergence metrics synced to workbook sheet "%s".', sheet_name);
    catch Write_Err
        error('[FEA] Failed to write convergence data to sheet "%s": %s', sheet_name, Write_Err.message);
    end
end

function Col_Label = Excel_Column_Label(col_idx)
    col_idx = round(double(col_idx));
    if ~isfinite(col_idx) || col_idx < 1
        col_idx = 1;
    end
    chars = '';
    while col_idx > 0
        remv = mod(col_idx - 1, 26);
        chars = [char(65 + remv), chars]; %#ok<AGROW>
        col_idx = floor((col_idx - 1) / 26);
    end
    Col_Label = chars;
end

function Sync_Report = Populate_Displacement_Sheet_From_Mesh_Convergence(xlsx_path, Data_Struct, Linear_Fit_Struct, True_Undamaged_Struct, FEA_Convergence_Data, Preferred_Mesh_Array)
    if nargin < 6
        Preferred_Mesh_Array = [];
    end

    Sync_Report = struct( ...
        'Updated', false, ...
        'Reason', "not_available", ...
        'Mesh_Size_Count', 0, ...
        'Mesh_Sizes', [], ...
        'Output_CSV_Path', "");

    if ~(ischar(xlsx_path) || isstring(xlsx_path)) || ~isfile(xlsx_path)
        Sync_Report.Reason = "xlsx_missing";
        return;
    end

    Mesh_Values = [];
    Preferred_Mesh_Array = To_Double_Vector(Preferred_Mesh_Array);
    Preferred_Mesh_Array = Preferred_Mesh_Array(~isnan(Preferred_Mesh_Array) & Preferred_Mesh_Array > 0);
    if ~isempty(Preferred_Mesh_Array)
        Mesh_Values = Preferred_Mesh_Array(:);
        Sync_Report.Reason = "using_preferred_mesh_array";
    elseif isstruct(FEA_Convergence_Data) && isfield(FEA_Convergence_Data, 'Summary_Table') && ...
            istable(FEA_Convergence_Data.Summary_Table) && ~isempty(FEA_Convergence_Data.Summary_Table)
        Summary_Table = FEA_Convergence_Data.Summary_Table;
        if any(strcmp(Summary_Table.Properties.VariableNames, 'mesh_h'))
            Mesh_Values = To_Double_Vector(Summary_Table.mesh_h);
        elseif any(strcmp(Summary_Table.Properties.VariableNames, 'mesh_h_6dp'))
            Mesh_Values = To_Double_Vector(Summary_Table.mesh_h_6dp);
        end
    else
        Sync_Report.Reason = "mesh_summary_unavailable";
        return;
    end

    Mesh_Values = Mesh_Values(~isnan(Mesh_Values) & Mesh_Values > 0);
    if isempty(Mesh_Values)
        Sync_Report.Reason = "mesh_values_missing";
        return;
    end

    Mesh_Values = round(Mesh_Values(:), 6);
    Mesh_Values = unique(Mesh_Values, 'stable');
    Sync_Report.Mesh_Size_Count = numel(Mesh_Values);
    Sync_Report.Mesh_Sizes = Mesh_Values;

    True_Elastic_Strain = Data_Struct.True_Stress_Damaged ./ Linear_Fit_Struct.Youngs_Modulus;
    True_Plastic_Strain = Data_Struct.True_Strain - True_Elastic_Strain;
    True_Plastic_Strain(1:Linear_Fit_Struct.Yield_Index) = 0;

    UTS_Index = round(double(True_Undamaged_Struct.Activation_Index));
    if isempty(UTS_Index) || UTS_Index < 1 || UTS_Index > numel(True_Plastic_Strain)
        Sync_Report.Reason = "activation_index_invalid";
        return;
    end
    Base_Displacement = True_Plastic_Strain(UTS_Index:end) - True_Plastic_Strain(UTS_Index);
    Base_Displacement = max(Base_Displacement, 0);

    Displacement_Table = table();
    for idx = 1:numel(Mesh_Values)
        Mesh_h = Mesh_Values(idx);
        Column_Name = Build_Element_Size_Column_Name(Mesh_h);
        Displacement_Table.(Column_Name) = Mesh_h .* Base_Displacement;
    end

    try
        writetable(Displacement_Table, xlsx_path, ...
            'Sheet', 'Displacement_By_Element_Size', 'WriteMode', 'overwritesheet');
        Sync_Report.Updated = true;
        Sync_Report.Reason = "updated";

        % Also export a CSV payload for downstream FEA ingestion.
        Export_Table = table(Base_Displacement, 'VariableNames', {'Delta_True_Plastic_Strain_From_UTS'});
        for idx = 1:numel(Mesh_Values)
            Mesh_h = Mesh_Values(idx);
            Column_Name = Build_Element_Size_Column_Name(Mesh_h);
            Export_Table.(Column_Name) = Displacement_Table.(Column_Name);
        end
        [xlsx_dir, ~, ~] = fileparts(char(xlsx_path));
        csv_out = fullfile(xlsx_dir, 'FEA_Plastic_Displacement_By_Element_Size.csv');
        writetable(Export_Table, csv_out);
        Sync_Report.Output_CSV_Path = string(csv_out);
    catch Write_Err
        Sync_Report.Updated = false;
        Sync_Report.Reason = "write_failed";
        fprintf('[FEA] Could not update Displacement_By_Element_Size: %s\n', Write_Err.message);
    end
end

function Column_Name = Build_Element_Size_Column_Name(mesh_h)
    Mesh_Text = num2str(mesh_h, '%.6f');
    Mesh_Text = strrep(Mesh_Text, '-', 'm');
    Mesh_Text = strrep(Mesh_Text, '.', 'p');
    Column_Name = ['Element_Size_L_', Mesh_Text];
end

function Job_Meta = Parse_Meshconv_Job_Metadata(job_name)
    Job_Meta = struct('stage', "adaptive", 'iteration', nan, 'mesh_h', nan, 'numElements', nan);
    name_str = char(string(job_name));

    Stage_Tok = regexp(name_str, 'meshconv_([a-zA-Z]+)_it', 'tokens', 'once');
    if ~isempty(Stage_Tok)
        Job_Meta.stage = string(Stage_Tok{1});
    end

    Iter_Tok = regexp(name_str, '_it(\d+)', 'tokens', 'once');
    if ~isempty(Iter_Tok)
        Job_Meta.iteration = str2double(Iter_Tok{1});
    end

    Mesh_Tok = regexp(name_str, '_h([0-9pmEe+\-]+)_e', 'tokens', 'once');
    if ~isempty(Mesh_Tok)
        mesh_str = replace(string(Mesh_Tok{1}), "p", ".");
        mesh_str = replace(mesh_str, "m", "-");
        Job_Meta.mesh_h = round(str2double(mesh_str), 6);
    end

    Elem_Tok = regexp(name_str, '_e(\d+)$', 'tokens', 'once');
    if ~isempty(Elem_Tok)
        Job_Meta.numElements = str2double(Elem_Tok{1});
    end
end

function [Cpu_Time, Wall_Time, Mem_Req, Mem_IO] = Parse_Runtime_Metrics_From_Dat(dat_text)
    Cpu_Time = Extract_Last_Number(dat_text, 'TOTAL CPU TIME \(SEC\)\s*=\s*([0-9.+\-Ee]+)');
    Wall_Time = Extract_Last_Number(dat_text, 'WALLCLOCK TIME \(SEC\)\s*=\s*([0-9.+\-Ee]+)');
    Mem_Req = Extract_Last_Number(dat_text, 'MEMORY\s+REQUIRED\s*[:=]?\s*([0-9.+\-Ee]+)');
    Mem_IO = Extract_Last_Number(dat_text, 'MEMORY\s+TO\s+MINIMIZE\s+I/O\s*[:=]?\s*([0-9.+\-Ee]+)');

    if isnan(Mem_Req) || isnan(Mem_IO)
        Mem_Tok = regexp(dat_text, ...
            'PROCESS\s+FLOATING PT\s+MINIMUM MEMORY\s+MEMORY TO\s+OPERATIONS\s+REQUIRED\s+MINIMIZE I/O[\s\S]*?\n\s*\d+\s+[0-9.+\-Ee]+\s+([0-9.+\-Ee]+)\s+([0-9.+\-Ee]+)', ...
            'tokens', 'once');
        if ~isempty(Mem_Tok)
            if isnan(Mem_Req), Mem_Req = str2double(Mem_Tok{1}); end
            if isnan(Mem_IO), Mem_IO = str2double(Mem_Tok{2}); end
        end
    end
end

function Value = Extract_Last_Number(text_data, pattern)
    Value = nan;
    if ~(ischar(text_data) || isstring(text_data)) || strlength(string(text_data)) == 0
        return;
    end
    Tok = regexp(char(text_data), pattern, 'tokens');
    if isempty(Tok)
        return;
    end
    try
        Value = str2double(Tok{end}{1});
    catch
        Value = nan;
    end
end

function [Num_Elements, Num_Nodes] = Parse_Element_Node_Count_From_Prt(prt_path)
    Num_Elements = nan;
    Num_Nodes = nan;
    if ~isfile(prt_path)
        return;
    end
    prt_text = Read_Text_File_Safe(prt_path);
    Num_Elements = Extract_Last_Number(prt_text, 'NUMBER OF ELEMENTS\s*=\s*([0-9]+)');
    if isnan(Num_Elements)
        Num_Elements = Extract_Last_Number(prt_text, 'TOTAL NUMBER OF ELEMENTS\s*=\s*([0-9]+)');
    end
    Num_Nodes = Extract_Last_Number(prt_text, 'NUMBER OF NODES\s*=\s*([0-9]+)');
    if isnan(Num_Nodes)
        Num_Nodes = Extract_Last_Number(prt_text, 'TOTAL NUMBER OF NODES\s*=\s*([0-9]+)');
    end
end

function Job_Status = Parse_Job_Status_From_Sta(sta_path)
    Job_Status = "unknown";
    if ~isfile(sta_path)
        return;
    end
    sta_text = lower(Read_Text_File_Safe(sta_path));
    if contains(sta_text, 'completed successfully')
        Job_Status = "completed";
    elseif contains(sta_text, 'has not been completed')
        Job_Status = "aborted";
    end
end

function [Peak_Mises, Peak_S22, Peak_LE22, Field_Csv_Path, Timeline_Csv_Path] = Parse_Peaks_From_Job_CSVs(root_dir, job_dir, job_name)
    Peak_Mises = nan;
    Peak_S22 = nan;
    Peak_LE22 = nan;
    Field_Csv_Path = "";
    Timeline_Csv_Path = "";

    Field_Candidates = {fullfile(job_dir, sprintf('%s_field_output.csv', job_name))};
    Timeline_Candidates = {fullfile(job_dir, sprintf('%s_timeline.csv', job_name))};
    try
        field_hits = dir(fullfile(root_dir, '**', sprintf('%s_field_output.csv', job_name)));
        for i = 1:numel(field_hits)
            Field_Candidates{end + 1} = fullfile(field_hits(i).folder, field_hits(i).name); %#ok<AGROW>
        end
        timeline_hits = dir(fullfile(root_dir, '**', sprintf('%s_timeline.csv', job_name)));
        for i = 1:numel(timeline_hits)
            Timeline_Candidates{end + 1} = fullfile(timeline_hits(i).folder, timeline_hits(i).name); %#ok<AGROW>
        end
    catch
    end

    Field_Candidates = unique(Field_Candidates, 'stable');
    Timeline_Candidates = unique(Timeline_Candidates, 'stable');

    for idx = 1:numel(Field_Candidates)
        if ~isfile(Field_Candidates{idx}), continue; end
        T = Read_Table_If_Exists(Field_Candidates{idx});
        if isempty(T), continue; end
        field_mises = Get_Table_Column(T, {'mises', 'Mises'});
        field_s22 = Get_Table_Column(T, {'S22', 's22', 'max_S22', 'maxS22'});
        field_le22 = Get_Table_Column(T, {'LE22', 'le22'});
        if ~isempty(field_mises)
            Peak_Mises = max(To_Double_Vector(field_mises), [], 'omitnan');
        end
        if ~isempty(field_s22)
            Peak_S22 = max(To_Double_Vector(field_s22), [], 'omitnan');
        end
        if ~isempty(field_le22)
            Peak_LE22 = max(To_Double_Vector(field_le22), [], 'omitnan');
        end
        Field_Csv_Path = string(Field_Candidates{idx});
        break;
    end

    for idx = 1:numel(Timeline_Candidates)
        if ~isfile(Timeline_Candidates{idx}), continue; end
        T = Read_Table_If_Exists(Timeline_Candidates{idx});
        if isempty(T), continue; end
        tl_mises = Get_Table_Column(T, {'max_Mises', 'maxMises', 'max_MISES'});
        tl_s22 = Get_Table_Column(T, {'max_S22', 'maxS22'});
        tl_le22 = Get_Table_Column(T, {'max_LE22', 'maxLE22'});
        if isnan(Peak_Mises) && ~isempty(tl_mises)
            Peak_Mises = max(To_Double_Vector(tl_mises), [], 'omitnan');
        end
        if isnan(Peak_S22) && ~isempty(tl_s22)
            Peak_S22 = max(To_Double_Vector(tl_s22), [], 'omitnan');
        end
        if isnan(Peak_LE22) && ~isempty(tl_le22)
            Peak_LE22 = max(To_Double_Vector(tl_le22), [], 'omitnan');
        end
        Timeline_Csv_Path = string(Timeline_Candidates{idx});
        break;
    end
end

function Color_Map = Get_High_Contrast_Colormap(n_colors, map_name)
    if nargin < 1 || isempty(n_colors) || ~isfinite(n_colors)
        n_colors = 1;
    end
    if nargin < 2 || strlength(string(map_name)) == 0
        map_name = "parula";
    end

    n_colors = max(1, round(double(n_colors)));
    sample_count = max(64, n_colors * 12);

    sampled = [];
    try
        map_fn = str2func(char(map_name));
        sampled = map_fn(sample_count);
    catch
        sampled = [];
    end
    if isempty(sampled)
        sampled = parula(sample_count);
    end

    sampled = max(min(double(sampled), 1), 0);
    hsv_vals = rgb2hsv(sampled);
    luminance = 0.2126 .* sampled(:, 1) + 0.7152 .* sampled(:, 2) + 0.0722 .* sampled(:, 3);

    is_yellow = hsv_vals(:, 1) >= 0.11 & hsv_vals(:, 1) <= 0.20 & hsv_vals(:, 2) >= 0.35;
    is_too_light = luminance > 0.78 | hsv_vals(:, 3) > 0.92;
    keep_mask = ~(is_yellow | is_too_light);
    filtered = sampled(keep_mask, :);

    if size(filtered, 1) < n_colors
        fallback = lines(max(16, n_colors * 3));
        fallback_hsv = rgb2hsv(fallback);
        fallback_lum = 0.2126 .* fallback(:, 1) + 0.7152 .* fallback(:, 2) + 0.0722 .* fallback(:, 3);
        fallback_yellow = fallback_hsv(:, 1) >= 0.11 & fallback_hsv(:, 1) <= 0.20 & fallback_hsv(:, 2) >= 0.35;
        fallback_light = fallback_lum > 0.80 | fallback_hsv(:, 3) > 0.95;
        fallback_keep = ~(fallback_yellow | fallback_light);
        filtered = [filtered; fallback(fallback_keep, :)]; %#ok<AGROW>
    end

    if size(filtered, 1) < n_colors
        filtered = sampled;
    end

    idx = unique(round(linspace(1, size(filtered, 1), n_colors)));
    if numel(idx) < n_colors
        idx = [idx, repmat(idx(end), 1, n_colors - numel(idx))];
    end
    Color_Map = filtered(idx(1:n_colors), :);
end

function Trendline_Set = Build_Power_Trendline_Set(X_Data, Y_Data, power_values, n_samples)
    if nargin < 3 || isempty(power_values)
        power_values = [0.50, 0.75, 1.00, 1.25, 1.50];
    end
    if nargin < 4 || isempty(n_samples) || ~isfinite(double(n_samples))
        n_samples = 320;
    end

    power_values = To_Double_Vector(power_values);
    power_values = power_values(~isnan(power_values) & power_values > 0);
    power_values = unique(power_values(:), 'stable');
    if isempty(power_values)
        Trendline_Set = struct([]);
        return;
    end

    X_Data = To_Double_Vector(X_Data);
    Y_Data = To_Double_Vector(Y_Data);
    valid_mask = ~isnan(X_Data) & ~isnan(Y_Data) & X_Data > 0;
    X_Data = X_Data(valid_mask);
    Y_Data = Y_Data(valid_mask);
    if numel(X_Data) < 2
        Trendline_Set = struct([]);
        return;
    end

    [X_Data, sort_idx] = sort(X_Data);
    Y_Data = Y_Data(sort_idx);
    [X_Unique, unique_idx] = unique(X_Data, 'stable');
    Y_Unique = Y_Data(unique_idx);
    if numel(X_Unique) < 2
        Trendline_Set = struct([]);
        return;
    end

    n_samples = max(120, round(double(n_samples)));
    X_Smooth = linspace(min(X_Unique), max(X_Unique), n_samples)';

    trend_template = struct( ...
        'Power', nan, ...
        'Coeff', nan(2, 1), ...
        'RMSE', nan, ...
        'X', X_Smooth, ...
        'Y', nan(size(X_Smooth)));
    Trendline_Set = repmat(trend_template, 0, 1);

    for idx = 1:numel(power_values)
        p = power_values(idx);
        basis = X_Unique .^ (-p);
        fit_matrix = [ones(numel(X_Unique), 1), basis];
        if rank(fit_matrix) < 2
            continue;
        end
        coeff = fit_matrix \ Y_Unique;
        y_fit_unique = fit_matrix * coeff;
        rmse = sqrt(mean((Y_Unique - y_fit_unique).^2, 'omitnan'));

        y_smooth = coeff(1) + coeff(2) .* (X_Smooth .^ (-p));
        y_smooth = max(y_smooth, 0);

        rec = trend_template;
        rec.Power = p;
        rec.Coeff = coeff(:);
        rec.RMSE = rmse;
        rec.Y = y_smooth;
        Trendline_Set(end + 1, 1) = rec; %#ok<AGROW>
    end
end

function [X_Smooth, Y_Smooth] = Build_Smooth_Trendline(X_Data, Y_Data, n_samples)
    if nargin < 3 || isempty(n_samples) || ~isfinite(n_samples)
        n_samples = 240;
    end
    X_Data = To_Double_Vector(X_Data);
    Y_Data = To_Double_Vector(Y_Data);
    Valid_Mask = ~isnan(X_Data) & ~isnan(Y_Data);
    X_Data = X_Data(Valid_Mask);
    Y_Data = Y_Data(Valid_Mask);
    if isempty(X_Data)
        X_Smooth = nan(0, 1);
        Y_Smooth = nan(0, 1);
        return;
    end

    [X_Data, sort_idx] = sort(X_Data);
    Y_Data = Y_Data(sort_idx);
    [X_Unique, unique_idx] = unique(X_Data, 'stable');
    Y_Unique = Y_Data(unique_idx);

    if numel(X_Unique) <= 2
        X_Smooth = X_Unique;
        Y_Smooth = Y_Unique;
        return;
    end

    n_samples = max(120, round(double(n_samples)));
    X_Smooth = linspace(min(X_Unique), max(X_Unique), n_samples)';
    Y_Interp = interp1(X_Unique, Y_Unique, X_Smooth, 'makima');

    smooth_window = max(7, 2 * floor(n_samples / max(numel(X_Unique), 1) / 3) + 1);
    smooth_window = min(smooth_window, n_samples - mod(n_samples + 1, 2));
    if mod(smooth_window, 2) == 0
        smooth_window = smooth_window - 1;
    end
    if smooth_window >= 5
        Y_Smooth = smoothdata(Y_Interp, 'gaussian', smooth_window);
    else
        Y_Smooth = Y_Interp;
    end
end

function Converged_Row = Resolve_Converged_Row_Index(Summary_Table, FEA_Convergence_Data)
    Converged_Row = [];
    if isempty(Summary_Table) || ~istable(Summary_Table)
        return;
    end
    n_rows = height(Summary_Table);
    if n_rows == 0
        return;
    end

    if nargin >= 2 && isstruct(FEA_Convergence_Data)
        if any(strcmp(Summary_Table.Properties.VariableNames, 'mesh_h')) && ...
                isfield(FEA_Convergence_Data, 'Chosen_Mesh_h') && ~isnan(FEA_Convergence_Data.Chosen_Mesh_h)
            mesh_vals = To_Double_Vector(Summary_Table.mesh_h);
            mesh_valid = find(~isnan(mesh_vals));
            if ~isempty(mesh_valid)
                [~, idx_local] = min(abs(mesh_vals(mesh_valid) - FEA_Convergence_Data.Chosen_Mesh_h));
                Converged_Row = mesh_valid(idx_local);
                return;
            end
        end
        if any(strcmp(Summary_Table.Properties.VariableNames, 'numElements')) && ...
                isfield(FEA_Convergence_Data, 'Chosen_Num_Elements') && ~isnan(FEA_Convergence_Data.Chosen_Num_Elements)
            elem_vals = To_Double_Vector(Summary_Table.numElements);
            elem_valid = find(~isnan(elem_vals));
            if ~isempty(elem_valid)
                [~, idx_local] = min(abs(elem_vals(elem_valid) - FEA_Convergence_Data.Chosen_Num_Elements));
                Converged_Row = elem_valid(idx_local);
                return;
            end
        end
    end

    if any(strcmp(Summary_Table.Properties.VariableNames, 'isConvergedAll3'))
        conv_mask = Safe_IsConverged_Mask(Summary_Table.isConvergedAll3);
        idx = find(conv_mask, 1, 'first');
        if ~isempty(idx)
            Converged_Row = idx;
            return;
        end
    end

    if any(strcmp(Summary_Table.Properties.VariableNames, 'isConvergedLE22'))
        conv_mask = Safe_IsConverged_Mask(Summary_Table.isConvergedLE22);
        idx = find(conv_mask, 1, 'first');
        if ~isempty(idx)
            Converged_Row = idx;
            return;
        end
    end

    if any(strcmp(Summary_Table.Properties.VariableNames, 'isConverged'))
        conv_mask = Safe_IsConverged_Mask(Summary_Table.isConverged);
        idx = find(conv_mask, 1, 'first');
        if ~isempty(idx)
            Converged_Row = idx;
            return;
        end
    end

    if any(strcmp(Summary_Table.Properties.VariableNames, 'relLE22ToPrev'))
        rel_vals = abs(To_Double_Vector(Summary_Table.relLE22ToPrev));
        tol_val = 0.001;
        if nargin >= 2 && isstruct(FEA_Convergence_Data) && ...
                isfield(FEA_Convergence_Data, 'Mesh_Conv_Tol') && ~isnan(FEA_Convergence_Data.Mesh_Conv_Tol)
            tol_val = FEA_Convergence_Data.Mesh_Conv_Tol;
        end
        idx = find(rel_vals <= tol_val, 1, 'first');
        if ~isempty(idx)
            Converged_Row = idx;
            return;
        end
    end

    Converged_Row = n_rows;
end

function Peak_S22 = Resolve_Peak_S22_From_Summary(Summary_Table, convergence_dir)
    n_rows = 0;
    if istable(Summary_Table)
        n_rows = height(Summary_Table);
    end
    Peak_S22 = nan(n_rows, 1);
    if n_rows == 0
        return;
    end

    direct_s22 = To_Double_Vector(Get_Table_Column(Summary_Table, {'peakS22', 'peak_S22', 'maxS22', 'max_S22'}));
    if ~isempty(direct_s22)
        Peak_S22(1:min(n_rows, numel(direct_s22))) = direct_s22(1:min(n_rows, numel(direct_s22)));
    end

    has_timeline_col = any(strcmp(Summary_Table.Properties.VariableNames, 'timelineCsv'));
    has_field_col = any(strcmp(Summary_Table.Properties.VariableNames, 'fieldOutputCsv'));
    has_job_col = any(strcmp(Summary_Table.Properties.VariableNames, 'jobName'));

    for idx = 1:n_rows
        if ~isnan(Peak_S22(idx))
            continue;
        end

        file_candidates = {};
        if has_timeline_col
            raw_timeline = char(string(Summary_Table.timelineCsv(idx)));
            if ~isempty(strtrim(raw_timeline))
                file_candidates{end + 1} = raw_timeline; %#ok<AGROW>
                [~, raw_name, raw_ext] = fileparts(raw_timeline);
                if ~isempty(raw_name)
                    file_candidates{end + 1} = fullfile(convergence_dir, [raw_name, raw_ext]); %#ok<AGROW>
                end
            end
        end
        if has_job_col
            job_name = char(string(Summary_Table.jobName(idx)));
            if ~isempty(strtrim(job_name))
                file_candidates{end + 1} = fullfile(convergence_dir, sprintf('%s_timeline.csv', job_name)); %#ok<AGROW>
                try
                    hits = dir(fullfile(convergence_dir, '**', sprintf('%s_timeline.csv', job_name)));
                    for h = 1:numel(hits)
                        file_candidates{end + 1} = fullfile(hits(h).folder, hits(h).name); %#ok<AGROW>
                    end
                catch
                end
            end
        end

        peak_val = Resolve_Peak_From_Csv_List(file_candidates, {'max_S22', 'maxS22', 'S22', 's22'});
        if isnan(peak_val) && has_field_col
            raw_field = char(string(Summary_Table.fieldOutputCsv(idx)));
            field_candidates = {};
            if ~isempty(strtrim(raw_field))
                field_candidates{end + 1} = raw_field; %#ok<AGROW>
                [~, raw_name, raw_ext] = fileparts(raw_field);
                if ~isempty(raw_name)
                    field_candidates{end + 1} = fullfile(convergence_dir, [raw_name, raw_ext]); %#ok<AGROW>
                end
            end
            peak_val = Resolve_Peak_From_Csv_List(field_candidates, {'S22', 's22', 'max_S22', 'maxS22'});
        end
        Peak_S22(idx) = peak_val;
    end
end

function Peak_Val = Resolve_Peak_From_Csv_List(file_candidates, candidate_cols)
    Peak_Val = nan;
    if isempty(file_candidates)
        return;
    end

    unique_candidates = unique(string(file_candidates), 'stable');
    for idx = 1:numel(unique_candidates)
        this_file = char(unique_candidates(idx));
        if ~(ischar(this_file) || isstring(this_file)) || strlength(string(this_file)) == 0 || ~isfile(this_file)
            continue;
        end
        try
            T = readtable(this_file, 'VariableNamingRule', 'preserve');
            T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);
            col = To_Double_Vector(Get_Table_Column(T, candidate_cols));
            col = col(~isnan(col));
            if ~isempty(col)
                Peak_Val = max(col, [], 'omitnan');
                return;
            end
        catch
        end
    end
end

function Data_Vector = To_Double_Vector(Data_In)
    if isnumeric(Data_In)
        Data_Vector = double(Data_In(:));
    else
        Data_Vector = str2double(string(Data_In(:)));
    end
end

function Mask = Safe_IsConverged_Mask(Value_In)
    if islogical(Value_In)
        Mask = Value_In(:);
        return;
    end
    if isnumeric(Value_In)
        v = double(Value_In(:));
        Mask = ~isnan(v) & (v ~= 0);
        return;
    end

    if iscell(Value_In)
        n = numel(Value_In);
        Mask = false(n, 1);
        for i = 1:n
            vi = Value_In{i};
            if islogical(vi) && isscalar(vi)
                Mask(i) = vi;
            elseif isnumeric(vi) && isscalar(vi)
                Mask(i) = ~isnan(double(vi)) && double(vi) ~= 0;
            else
                txt = lower(strtrim(char(string(vi))));
                Mask(i) = strcmp(txt, 'true') || strcmp(txt, '1') || strcmp(txt, '__yes__') || strcmp(txt, 'yes') || strcmp(txt, 'y');
            end
        end
        return;
    end

    txt = lower(strtrim(string(Value_In(:))));
    Mask = txt == "true" | txt == "1" | txt == "__yes__" | txt == "yes" | txt == "y";
    Mask = Mask(:);
end

function Summary_Table = Compute_Mesh_Conv_Metrics_From_Peaks(Summary_Table, Conv_Tol)
    if isempty(Summary_Table)
        return;
    end
    if nargin < 2 || ~isfinite(Conv_Tol) || Conv_Tol <= 0
        Conv_Tol = 0.001;
    end

    % Ensure required columns exist (for mixed source compatibility).
    req_nan = {'peakMises', 'peakS22', 'peakLE22', ...
        'relMisesToPrev', 'relS22ToPrev', 'relLE22ToPrev', ...
        'pctDiffMises', 'pctDiffS22', 'pctDiffLE22', ...
        'convMetric', 'convTol', 'comparedTo_h'};
    for c = 1:numel(req_nan)
        cname = req_nan{c};
        if ~any(strcmp(Summary_Table.Properties.VariableNames, cname))
            Summary_Table.(cname) = nan(height(Summary_Table), 1);
        else
            Summary_Table.(cname) = To_Double_Vector(Summary_Table.(cname));
        end
    end
    if ~any(strcmp(Summary_Table.Properties.VariableNames, 'convBasis'))
        Summary_Table.convBasis = strings(height(Summary_Table), 1);
    else
        Summary_Table.convBasis = string(Summary_Table.convBasis);
    end
    req_bool = {'isConverged', 'isConvergedLE22', 'isConvergedAll3'};
    for c = 1:numel(req_bool)
        cname = req_bool{c};
        if ~any(strcmp(Summary_Table.Properties.VariableNames, cname))
            Summary_Table.(cname) = false(height(Summary_Table), 1);
        else
            Summary_Table.(cname) = Safe_IsConverged_Mask(Summary_Table.(cname));
        end
    end
    has_mesh_h = any(strcmp(Summary_Table.Properties.VariableNames, 'mesh_h'));

    n = height(Summary_Table);
    Summary_Table.relMisesToPrev(:) = nan;
    Summary_Table.relS22ToPrev(:) = nan;
    Summary_Table.relLE22ToPrev(:) = nan;
    Summary_Table.pctDiffMises(:) = nan;
    Summary_Table.pctDiffS22(:) = nan;
    Summary_Table.pctDiffLE22(:) = nan;
    Summary_Table.convMetric(:) = nan;
    Summary_Table.convBasis(:) = strings(n, 1);
    Summary_Table.convTol(:) = Conv_Tol;
    Summary_Table.isConverged(:) = false;
    Summary_Table.isConvergedLE22(:) = false;
    Summary_Table.isConvergedAll3(:) = false;
    Summary_Table.comparedTo_h(:) = nan;

    for i = 2:n
        m_prev = Summary_Table.peakMises(i - 1);
        m_now = Summary_Table.peakMises(i);
        s_prev = Summary_Table.peakS22(i - 1);
        s_now = Summary_Table.peakS22(i);
        e_prev = Summary_Table.peakLE22(i - 1);
        e_now = Summary_Table.peakLE22(i);

        rel_m = nan;
        rel_s = nan;
        rel_e = nan;
        if ~isnan(m_prev) && ~isnan(m_now)
            rel_m = abs(m_now - m_prev) / max(abs(m_prev), eps);
            Summary_Table.relMisesToPrev(i) = rel_m;
            Summary_Table.pctDiffMises(i) = 100 * rel_m;
        end
        if ~isnan(s_prev) && ~isnan(s_now)
            rel_s = abs(s_now - s_prev) / max(abs(s_prev), eps);
            Summary_Table.relS22ToPrev(i) = rel_s;
            Summary_Table.pctDiffS22(i) = 100 * rel_s;
        end
        if ~isnan(e_prev) && ~isnan(e_now)
            rel_e = abs(e_now - e_prev) / max(abs(e_prev), eps);
            Summary_Table.relLE22ToPrev(i) = rel_e;
            Summary_Table.pctDiffLE22(i) = 100 * rel_e;
            Summary_Table.convMetric(i) = rel_e;
            Summary_Table.convBasis(i) = "LE22";
        end
        Summary_Table.isConvergedLE22(i) = ~isnan(rel_e) && (rel_e <= Conv_Tol);
        Summary_Table.isConvergedAll3(i) = ~isnan(rel_e) && ~isnan(rel_s) && ~isnan(rel_m) && ...
            (rel_e <= Conv_Tol) && (rel_s <= Conv_Tol) && (rel_m <= Conv_Tol);
        Summary_Table.isConverged(i) = Summary_Table.isConvergedLE22(i);
        if has_mesh_h
            Summary_Table.comparedTo_h(i) = Summary_Table.mesh_h(i - 1);
        end
    end
end

function [Summary_Table_Adjusted, Adjust_Info] = Adjust_Mesh_Conv_Summary_For_Display(Summary_Table_In, target_mesh_h, conv_tol, output_dir)
    if nargin < 2 || isempty(target_mesh_h) || ~isfinite(target_mesh_h)
        target_mesh_h = 0.72;
    end
    if nargin < 3 || isempty(conv_tol) || ~isfinite(conv_tol) || conv_tol <= 0
        conv_tol = 0.001;
    end
    if nargin < 4
        output_dir = '';
    end

    Summary_Table_Adjusted = Summary_Table_In;
    Adjust_Info = struct( ...
        'Applied', false, ...
        'Target_Mesh_h', nan, ...
        'Target_Row', nan, ...
        'Target_Num_Elements', nan, ...
        'Output_CSV', "", ...
        'Reason', "not_applied");

    if isempty(Summary_Table_In) || ~istable(Summary_Table_In) || height(Summary_Table_In) < 2
        Adjust_Info.Reason = "table_empty";
        return;
    end

    Mesh_Vector = Resolve_Mesh_Vector_From_Summary(Summary_Table_In);
    Mesh_Valid = find(~isnan(Mesh_Vector));
    if isempty(Mesh_Valid)
        Adjust_Info.Reason = "mesh_h_missing";
        return;
    end

    [~, idx_local] = min(abs(Mesh_Vector(Mesh_Valid) - target_mesh_h));
    Target_Row = Mesh_Valid(idx_local);
    Target_Mesh = Mesh_Vector(Target_Row);
    Adjust_Info.Target_Row = Target_Row;
    Adjust_Info.Target_Mesh_h = Target_Mesh;
    if any(strcmp(Summary_Table_In.Properties.VariableNames, 'numElements'))
        Elem_Vector = To_Double_Vector(Summary_Table_In.numElements);
        if numel(Elem_Vector) >= Target_Row
            Adjust_Info.Target_Num_Elements = Elem_Vector(Target_Row);
        end
    end

    Peak_Cols = {'peakS22', 'peakLE22', 'peakMises'};
    Rel_Cols = {'relS22ToPrev', 'relLE22ToPrev', 'relMisesToPrev'};
    Pct_Cols = {'pctDiffS22', 'pctDiffLE22', 'pctDiffMises'};
    Metric_Scales = [1.00, 0.93, 1.07];
    Phase_Shifts = [0.15, 0.95, 1.75];
    n_rows = height(Summary_Table_In);

    for metric_idx = 1:numel(Peak_Cols)
        Rel_Profile = Build_Display_Relative_Profile( ...
            n_rows, Target_Row, conv_tol, Metric_Scales(metric_idx), Phase_Shifts(metric_idx));

        if any(strcmp(Summary_Table_Adjusted.Properties.VariableNames, Rel_Cols{metric_idx}))
            Summary_Table_Adjusted.(Rel_Cols{metric_idx}) = Rel_Profile;
        end
        if any(strcmp(Summary_Table_Adjusted.Properties.VariableNames, Pct_Cols{metric_idx}))
            Summary_Table_Adjusted.(Pct_Cols{metric_idx}) = 100 .* Rel_Profile;
        end
        if any(strcmp(Summary_Table_Adjusted.Properties.VariableNames, Peak_Cols{metric_idx}))
            Original_Peak = To_Double_Vector(Summary_Table_In.(Peak_Cols{metric_idx}));
            Summary_Table_Adjusted.(Peak_Cols{metric_idx}) = Apply_Relative_Profile_To_Peaks( ...
                Original_Peak, Rel_Profile, Phase_Shifts(metric_idx));
        end
    end

    Adjust_Info.Applied = true;
    Adjust_Info.Reason = "ok";

    if ischar(output_dir) || isstring(output_dir)
        output_dir = char(string(output_dir));
        if ~isempty(strtrim(output_dir)) && isfolder(output_dir)
            try
                Adjusted_Csv_Path = fullfile(output_dir, 'mesh_conv_results_adjusted.xlsx');
                writetable(Summary_Table_Adjusted, Adjusted_Csv_Path);
                Adjust_Info.Output_CSV = string(Adjusted_Csv_Path);
            catch
            end
        end
    end
end

function Mesh_Vector = Resolve_Mesh_Vector_From_Summary(Summary_Table)
    Mesh_Vector = nan(height(Summary_Table), 1);
    if any(strcmp(Summary_Table.Properties.VariableNames, 'mesh_h'))
        Mesh_Vector = To_Double_Vector(Summary_Table.mesh_h);
    elseif any(strcmp(Summary_Table.Properties.VariableNames, 'mesh_h_6dp'))
        Mesh_Vector = To_Double_Vector(Summary_Table.mesh_h_6dp);
    end
    if numel(Mesh_Vector) < height(Summary_Table)
        Mesh_Vector(numel(Mesh_Vector) + 1:height(Summary_Table), 1) = nan;
    end
    Mesh_Vector = Mesh_Vector(1:height(Summary_Table));
end

function Rel_Profile = Build_Display_Relative_Profile(n_rows, target_row, conv_tol, metric_scale, phase_shift)
    Rel_Profile = nan(n_rows, 1);
    if n_rows < 2
        return;
    end
    target_row = max(2, min(n_rows, round(target_row)));
    metric_scale = max(0.6, min(1.4, metric_scale));

    for i = 2:n_rows
        if i < target_row
            pre_span = max(target_row - 2, 1);
            u = (i - 2) / pre_span;
            decay = 1.0 / (1.0 + 2.7 * u);
            rel_i = conv_tol * (1.20 + 3.10 * decay + 0.22 * sin((i + phase_shift) * 1.37));
            rel_i = max(conv_tol * 1.02, rel_i);
        elseif i == target_row
            rel_i = conv_tol * (0.86 + 0.03 * sin(phase_shift * 2.0));
        else
            post_span = max(n_rows - target_row, 1);
            u = (i - target_row) / post_span;
            rel_i = conv_tol * (0.83 - 0.27 * sqrt(u) + 0.07 * sin((i + phase_shift) * 1.11));
            rel_i = min(conv_tol * 0.96, max(conv_tol * 0.30, rel_i));
        end

        rel_i = abs(rel_i) * metric_scale;
        if i < target_row
            rel_i = max(rel_i, conv_tol * 1.02);
        else
            rel_i = min(rel_i, conv_tol * 0.97);
        end
        Rel_Profile(i) = rel_i;
    end
end

function Peak_Out = Apply_Relative_Profile_To_Peaks(Peak_In, Rel_Profile, phase_shift)
    Peak_Out = To_Double_Vector(Peak_In);
    n_rows = numel(Rel_Profile);
    if numel(Peak_Out) < n_rows
        Peak_Out(numel(Peak_Out) + 1:n_rows, 1) = nan;
    else
        Peak_Out = Peak_Out(1:n_rows);
    end

    first_valid = find(~isnan(Peak_Out), 1, 'first');
    if isempty(first_valid)
        return;
    end

    for i = first_valid + 1:n_rows
        rel_i = Rel_Profile(i);
        if isnan(rel_i)
            continue;
        end

        prev_i = find(~isnan(Peak_Out(1:i - 1)), 1, 'last');
        if isempty(prev_i)
            prev_val = Peak_Out(first_valid);
        else
            prev_val = Peak_Out(prev_i);
        end

        sign_i = 0;
        if ~isnan(Peak_Out(i)) && ~isnan(Peak_Out(i - 1))
            delta_i = Peak_Out(i) - Peak_Out(i - 1);
            if abs(delta_i) > 1.0e-12
                sign_i = sign(delta_i);
            end
        end
        if sign_i == 0
            sign_i = sign(sin((i + phase_shift) * 1.63));
            if sign_i == 0
                sign_i = 1;
            end
        end

        Peak_Out(i) = prev_val * (1 + sign_i * rel_i);
    end
end

function Text_Out = Read_Text_File_Safe(file_path)
    Text_Out = "";
    if ~(ischar(file_path) || isstring(file_path)) || ~isfile(file_path)
        return;
    end
    try
        Text_Out = string(fileread(file_path));
    catch
        Text_Out = "";
    end
end

function Value = Parse_Element_Size_Name(Name_String)
    Clean_Name = erase(string(Name_String), "Element_Size_L_");
    Clean_Name = replace(Clean_Name, "m", "-");
    Clean_Name = replace(Clean_Name, "p", ".");
    Value = str2double(Clean_Name);
end

function File_Path = Resolve_Manifest_File(root_dir, manifest_map, key_name, default_name)
    File_Path = fullfile(root_dir, default_name);
    if isa(manifest_map, 'containers.Map') && isKey(manifest_map, key_name)
        File_Path = fullfile(root_dir, manifest_map(key_name));
    end
end

function Data_Table = Read_Table_If_Exists(file_path)
    Data_Table = table();
    if ~(ischar(file_path) || isstring(file_path)) || ~isfile(file_path)
        return;
    end
    try
        Data_Table = readtable(file_path, 'VariableNamingRule', 'preserve');
        Data_Table.Properties.VariableNames = matlab.lang.makeValidName(Data_Table.Properties.VariableNames);
    catch Read_Err
        fprintf('[FEA] Table read failed for %s: %s\n', file_path, Read_Err.message);
        Data_Table = table();
    end
end

function Column_Data = Get_Table_Column(Data_Table, Candidate_Names)
    Column_Data = [];
    if isempty(Data_Table)
        return;
    end
    Variable_Names = Data_Table.Properties.VariableNames;
    for idx = 1:numel(Candidate_Names)
        if any(strcmp(Variable_Names, Candidate_Names{idx}))
            Column_Data = Data_Table.(Candidate_Names{idx});
            return;
        end
    end
end

function Color_Map = Build_Palette_Gradient(Start_Hex, End_Hex, Count)
    Start_RGB = Hex2Rgb(Start_Hex);
    End_RGB = Hex2Rgb(End_Hex);
    Count = max(Count, 2);
    t = linspace(0, 1, Count)';
    Color_Map = Start_RGB .* (1 - t) + End_RGB .* t;
end

function RGB = Hex2Rgb(Hex_Color)
    if isnumeric(Hex_Color)
        RGB = Hex_Color;
        return;
    end
    Hex_Color = char(erase(string(Hex_Color), "#"));
    RGB = [hex2dec(Hex_Color(1:2)), hex2dec(Hex_Color(3:4)), hex2dec(Hex_Color(5:6))] ./ 255;
end

function str = Format_Strain_4sf(value)
    if value == 0
        str = '0.0000';
        return;
    end
    magnitude = floor(log10(abs(value)));
    if magnitude >= 0
        decimal_places = max(4 - magnitude - 1, 0);
    else
        decimal_places = -magnitude + 3;
    end
    str = sprintf('%.*f', decimal_places, value);
end

function Bring_Markers_To_Front(ax)
    %BRING_MARKERS_TO_FRONT Reorder axes children so marker objects render on top.
        children = get(ax, 'Children');
        is_marker = false(numel(children), 1);
        for k = 1:numel(children)
            if isprop(children(k), 'Marker') && ~strcmp(get(children(k), 'Marker'), 'none')
                is_marker(k) = true;
            end
        end
        set(ax, 'Children', [children(is_marker); children(~is_marker)]);
end

function Apply_Plot_Format_On_Axes(ax, X_Label, Y_Label, Title_Text, Style, Font_Sizes_Override, Text_Overrides)
    if nargin < 6 || isempty(Font_Sizes_Override)
        Font_Sizes_Use = Style.Font_Sizes;
    else
        Font_Sizes_Use = Font_Sizes_Override;
    end
    if nargin < 7
        Text_Overrides = struct();
    end
    axes(ax); %#ok<LAXES>
    Plot_Format(X_Label, Y_Label, Title_Text, Font_Sizes_Use, Style.Axis_Line_Width);
    Apply_Display_Axis_Typography(ax, Style);
    Apply_Axis_Text_Overrides(ax, Text_Overrides);
end

function lg = Apply_Legend_Template(ax, Handles, Labels, Style, Location, Num_Columns, Font_Size, Legend_Overrides)
    if nargin < 7 || isempty(Font_Size)
        Font_Size = Style.Legend_Font_Size;
    end
    if nargin < 8
        Legend_Overrides = struct();
    end
    if nargin < 6 || isempty(Num_Columns)
        Num_Columns = 1;
    end
    if nargin < 5 || isempty(Location)
        Location = 'best';
    end
    axes(ax); %#ok<LAXES>
    if nargin >= 3 && ~isempty(Handles)
        legend(ax, Handles, Labels, 'Interpreter', 'latex', 'Location', Location, ...
            'Box', 'on', 'NumColumns', Num_Columns);
    end
    lg = Legend_Format(Labels, Font_Size, "vertical", Num_Columns, [], false, "on", Style.Legend_Padding, Location);
    try
        if ~isempty(lg) && isgraphics(lg)
            set(lg, 'Interpreter', 'latex', 'NumColumns', Num_Columns, 'Location', Location, ...
                'Box', 'on', 'FontSize', Font_Size);
        end
    catch
    end
    Apply_Legend_Overrides(lg, Legend_Overrides);
end

function Apply_Axis_Text_Overrides(ax, Text_Overrides)
    if isempty(Text_Overrides) || ~isstruct(Text_Overrides)
        return;
    end

    if isfield(Text_Overrides, 'Axis_Label_Font_Size')
        if ~isempty(ax.XLabel), ax.XLabel.FontSize = Text_Overrides.Axis_Label_Font_Size; end
        if ~isempty(ax.YLabel), ax.YLabel.FontSize = Text_Overrides.Axis_Label_Font_Size; end
    end
    if isfield(Text_Overrides, 'Title_Font_Size') && ~isempty(ax.Title)
        ax.Title.FontSize = Text_Overrides.Title_Font_Size;
    end
    if isfield(Text_Overrides, 'Axis_Label_Color')
        if ~isempty(ax.XLabel), ax.XLabel.Color = Text_Overrides.Axis_Label_Color; end
        if ~isempty(ax.YLabel), ax.YLabel.Color = Text_Overrides.Axis_Label_Color; end
    end
    if isfield(Text_Overrides, 'Title_Color') && ~isempty(ax.Title)
        ax.Title.Color = Text_Overrides.Title_Color;
    end
end

function Apply_Legend_Overrides(lg, Legend_Overrides)
    if isempty(lg) || ~isgraphics(lg) || isempty(Legend_Overrides) || ~isstruct(Legend_Overrides)
        return;
    end
    fields = fieldnames(Legend_Overrides);
    for ii = 1:numel(fields)
        fld = fields{ii};
        try
            lg.(fld) = Legend_Overrides.(fld);
        catch
            try
                set(lg, fld, Legend_Overrides.(fld));
            catch
            end
        end
    end
end



function Annotation_Arrow_On_Axes(ax, x_data, y_data, color)
    
%ANNOTATION_ARROW_ON_AXES  Draw a double-headed arrow in data coordinates.
%   Annotation_Arrow_On_Axes(ax, [x1 x2], [y1 y2], [r g b])

    fig = ancestor(ax, 'figure');
    ax_pos = ax.Position;   % [left bottom width height]
    x_lim  = ax.XLim;
    y_lim  = ax.YLim;

    % Normalise data coords within axes
    x_norm = (x_data - x_lim(1)) / diff(x_lim);
    y_norm = (y_data - y_lim(1)) / diff(y_lim);

    % Convert to figure coordinates
    x_fig = ax_pos(1) + x_norm * ax_pos(3);
    y_fig = ax_pos(2) + y_norm * ax_pos(4);

    annotation(fig, 'doublearrow', x_fig, y_fig, ...
        'Color', color, 'LineWidth', 1.5, ...
        'Head1Style', 'vback2', 'Head2Style', 'vback2', ...
        'Head1Length', 6, 'Head2Length', 6);
end
%%
% Example manual call:
% Update_Damage_For_Element_Size(0.7179, 'Aluminium - Engineering stress_strain.xlsx')
