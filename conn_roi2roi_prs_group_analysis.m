%% conn_roi2roi_prs_group_analysis.m
% 批量读取 CONN ROI-to-ROI matrix，并对每个连接拟合模型：
%   FC ~ PRS + Group + PRS:Group
% 输出显著连接（默认 FDR q < 0.05）
%
% 使用说明：
% 1) 准备一个被试信息表（CSV/XLSX），至少包含列：
%       SubjectID, PRS, Group
%    其中 Group 可为数值(0/1)或类别字符串。
%
% 2) 每个被试一个 ROI-to-ROI 矩阵文件（.mat），文件名中包含 SubjectID。
%    脚本会自动读取第一个二维方阵变量作为 FC 矩阵。
%
% 3) 修改下面“用户参数区”后运行。
%
% 作者：ChatGPT

%% ======================= 用户参数区 =======================
matrixDir   = './conn_matrices';          % ROI-to-ROI 矩阵文件夹
matrixExt   = '*.mat';                    % 矩阵文件扩展名
subjectFile = './subjects.csv';           % 被试信息表
outDir      = './results_conn_prs';       % 输出目录
alphaFDR    = 0.05;                       % FDR 阈值
saveAllStats = true;                      % 是否保存全连接统计结果
%% =========================================================

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% 读取被试信息
fprintf('读取被试信息: %s\n', subjectFile);
if endsWith(lower(subjectFile), '.csv')
    T = readtable(subjectFile);
else
    T = readtable(subjectFile, 'FileType', 'spreadsheet');
end

requiredCols = {'SubjectID','PRS','Group'};
for i = 1:numel(requiredCols)
    if ~ismember(requiredCols{i}, T.Properties.VariableNames)
        error('被试信息缺少必要列: %s', requiredCols{i});
    end
end

% 标准化列类型
T.SubjectID = string(T.SubjectID);
if ~iscategorical(T.Group)
    T.Group = categorical(T.Group);
end

%% 匹配 ROI-to-ROI 矩阵文件
files = dir(fullfile(matrixDir, matrixExt));
if isempty(files)
    error('在目录 %s 下未找到 %s 文件。', matrixDir, matrixExt);
end

nSub = height(T);
matData = cell(nSub,1);
hasMat  = false(nSub,1);

fprintf('匹配并读取 ROI-to-ROI 矩阵...\n');
for s = 1:nSub
    sid = T.SubjectID(s);
    hit = contains(string({files.name}), sid, 'IgnoreCase', true);
    idx = find(hit, 1, 'first');
    if isempty(idx)
        warning('未找到被试 %s 的矩阵文件，跳过。', sid);
        continue;
    end

    fpath = fullfile(files(idx).folder, files(idx).name);
    M = load_first_square_matrix(fpath);
    matData{s} = M;
    hasMat(s) = true;
end

T = T(hasMat,:);
matData = matData(hasMat);
nSub = height(T);

if nSub < 5
    error('有效被试数过少（%d），无法稳定拟合模型。', nSub);
end

%% 检查矩阵维度一致
dims = cellfun(@(x) size(x,1), matData);
if any(cellfun(@(x) size(x,1) ~= size(x,2), matData))
    error('存在非方阵 ROI-to-ROI 矩阵。');
end
if numel(unique(dims)) ~= 1
    error('ROI 数量不一致，请检查输入矩阵维度。');
end
nROI = dims(1);

%% 组装 3D 数据: ROI x ROI x Subject
FC = nan(nROI, nROI, nSub);
for s = 1:nSub
    FC(:,:,s) = matData{s};
end

%% 为每条连接拟合模型
% 使用 fitlm 的公式接口，关注交互项 PRS:Group
fprintf('开始逐连接拟合: FC ~ PRS + Group + PRS:Group\n');

nEdge = nROI*(nROI-1)/2;
edge_i = zeros(nEdge,1);
edge_j = zeros(nEdge,1);
beta_prs = nan(nEdge,1);
p_prs    = nan(nEdge,1);
beta_grp = nan(nEdge,1);
p_grp    = nan(nEdge,1);
beta_int = nan(nEdge,1);
p_int    = nan(nEdge,1);

k = 0;
for i = 1:nROI-1
    for j = i+1:nROI
        k = k + 1;
        y = squeeze(FC(i,j,:));

        valid = ~isnan(y) & ~isnan(T.PRS) & ~isundefined(T.Group);
        if nnz(valid) < 5
            continue;
        end

        tbl = table(y(valid), T.PRS(valid), T.Group(valid), ...
            'VariableNames', {'FC','PRS','Group'});

        mdl = fitlm(tbl, 'FC ~ PRS + Group + PRS:Group');
        coef = mdl.Coefficients;

        edge_i(k) = i;
        edge_j(k) = j;

        [beta_prs(k), p_prs(k)] = get_coef(coef, 'PRS');

        % Group 若有多水平会对应多个哑变量，这里保存第一个 Group 主效应
        grpRows = startsWith(coef.Properties.RowNames, 'Group_');
        if any(grpRows)
            row = find(grpRows,1,'first');
            beta_grp(k) = coef.Estimate(row);
            p_grp(k)    = coef.pValue(row);
        end

        % 交互项：匹配以 'PRS:Group_' 开头的系数（多水平组时取第一个）
        intRows = startsWith(coef.Properties.RowNames, 'PRS:Group_') | ...
                  startsWith(coef.Properties.RowNames, 'Group_:PRS');
        if any(intRows)
            row = find(intRows,1,'first');
            beta_int(k) = coef.Estimate(row);
            p_int(k)    = coef.pValue(row);
        else
            % 某些编码下可能命名为 'PRS:Group'
            [beta_int(k), p_int(k)] = get_coef(coef, 'PRS:Group');
        end
    end
end

R = table(edge_i, edge_j, beta_prs, p_prs, beta_grp, p_grp, beta_int, p_int, ...
    'VariableNames', {'ROI_i','ROI_j','Beta_PRS','P_PRS','Beta_Group','P_Group','Beta_Interaction','P_Interaction'});

% 去掉未拟合条目
R = R(R.ROI_i>0,:);

%% 多重比较校正（默认对交互项做 FDR）
[~, ~, pFDR_int] = fdr_bh(R.P_Interaction);
R.P_Interaction_FDR = pFDR_int;

sigR = R(R.P_Interaction_FDR < alphaFDR, :);
sigR = sortrows(sigR, 'P_Interaction_FDR');

%% 输出
if saveAllStats
    writetable(R, fullfile(outDir, 'all_edges_stats.csv'));
end
writetable(sigR, fullfile(outDir, 'significant_edges_interaction.csv'));

fprintf('完成。总连接数: %d\n', height(R));
fprintf('显著交互连接数 (FDR < %.3f): %d\n', alphaFDR, height(sigR));
fprintf('输出目录: %s\n', outDir);

%% ======================= 本地函数 =========================
function M = load_first_square_matrix(fpath)
    S = load(fpath);
    fns = fieldnames(S);
    for ii = 1:numel(fns)
        x = S.(fns{ii});
        if isnumeric(x) && ismatrix(x) && size(x,1)==size(x,2) && size(x,1)>1
            M = x;
            return;
        end
    end
    error('文件中未找到二维方阵变量: %s', fpath);
end

function [b, p] = get_coef(coefTable, rowName)
    b = nan; p = nan;
    row = strcmp(coefTable.Properties.RowNames, rowName);
    if any(row)
        idx = find(row,1,'first');
        b = coefTable.Estimate(idx);
        p = coefTable.pValue(idx);
    end
end

function [h, crit_p, adj_p] = fdr_bh(pvals, q)
    % Benjamini-Hochberg FDR
    if nargin < 2, q = 0.05; end
    p = pvals(:);
    nanMask = isnan(p);
    p2 = p(~nanMask);
    m = numel(p2);

    [ps, idx] = sort(p2);
    thr = (1:m)'/m*q;
    w = find(ps <= thr, 1, 'last');

    h2 = false(m,1);
    if ~isempty(w)
        h2(ps <= ps(w)) = true;
        crit_p = ps(w);
    else
        crit_p = 0;
    end

    % 计算调整后 p 值（单调递增修正）
    adjRaw = (m./(1:m)') .* ps;
    adjMon = zeros(m,1);
    adjMon(end) = min(1, adjRaw(end));
    for ii = m-1:-1:1
        adjMon(ii) = min(adjMon(ii+1), adjRaw(ii));
    end
    adj2 = nan(m,1);
    adj2(idx) = adjMon;

    h = false(size(p));
    h(~nanMask) = h2;

    adj_p = nan(size(p));
    adj_p(~nanMask) = adj2;
end
