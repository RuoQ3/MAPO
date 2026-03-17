classdef ResultsAnalyzer < handle
    % ResultsAnalyzer 结果解读与决策辅助
    %
    % 功能:
    %   - Pareto前沿统计分析
    %   - 敏感性分析
    %   - 权衡分析
    %   - 推荐解选择
    %
    % 示例:
    %   analyzer = ResultsAnalyzer();
    %   stats = analyzer.analyzeParetoFront(results);
    %   recommendation = analyzer.recommendSolution(results);

    properties (Access = private)
        results            % 优化结果
        paretoFront        % Pareto前沿
        problemDef         % 问题定义
    end

    methods
        function obj = ResultsAnalyzer()
            % ResultsAnalyzer 构造函数

            obj.results = [];
            obj.paretoFront = [];
            obj.problemDef = [];
        end

        function setResults(obj, results, problemDef)
            % setResults 设置优化结果和问题定义
            %
            % 输入:
            %   results - 优化结果struct
            %   problemDef - OptimizationProblem对象

            obj.results = results;
            obj.problemDef = problemDef;

            if isfield(results, 'paretoFront')
                obj.paretoFront = results.paretoFront;
            end
        end

        function stats = analyzeParetoFront(obj, results)
            % analyzeParetoFront Pareto前沿分析
            %
            % 输入:
            %   results - 优化结果struct
            %
            % 输出:
            %   stats - 分析统计struct

            obj.setResults(results, []);

            stats = struct();

            if ~isfield(results, 'paretoFront') || isempty(results.paretoFront)
                stats.solutionCount = 0;
                stats.message = 'Pareto前沿为空';
                return;
            end

            front = results.paretoFront;

            % 基本统计
            stats.solutionCount = size(front, 1);
            stats.objectiveCount = size(front, 2);

            % 目标值统计
            stats.objectives = struct();
            for i = 1:size(front, 2)
                obj_col = front(:, i);
                obj_col = obj_col(isfinite(obj_col));

                stats.objectives(i).index = i;
                stats.objectives(i).min = min(obj_col);
                stats.objectives(i).max = max(obj_col);
                stats.objectives(i).mean = mean(obj_col);
                stats.objectives(i).std = std(obj_col);
                stats.objectives(i).range = stats.objectives(i).max - stats.objectives(i).min;
            end

            % 多样性指标（拥挤距离）
            if isfield(results, 'crowdingDistances')
                stats.diversity = struct();
                distances = results.crowdingDistances;
                stats.diversity.meanCrowding = mean(distances);
                stats.diversity.minCrowding = min(distances);
                stats.diversity.maxCrowding = max(distances);
            end

            % 收敛性指标
            stats.convergenceQuality = obj.calculateConvergenceQuality(front);

            % 可行性
            if isfield(results, 'feasibility')
                stats.feasibilityRatio = mean(results.feasibility);
            else
                stats.feasibilityRatio = 1.0;
            end
        end

        function sensitivity = sensitivityAnalysis(obj, results)
            % sensitivityAnalysis 敏感性分析
            %
            % 输入:
            %   results - 优化结果struct
            %
            % 输出:
            %   sensitivity - 敏感性分析结果struct

            sensitivity = struct();

            if ~isfield(results, 'paretoFront') || ~isfield(results, 'paretoFrontVariables')
                sensitivity.status = 'unavailable';
                sensitivity.message = '缺少必要的Pareto解数据';
                return;
            end

            front = results.paretoFront;
            frontVars = results.paretoFrontVariables;

            % 计算变量在Pareto前沿中的变化范围
            sensitivity.variableSensitivity = struct();

            if ~isempty(frontVars)
                nVars = size(frontVars, 2);
                sensitivity_scores = [];

                for i = 1:nVars
                    var_col = frontVars(:, i);
                    var_range = max(var_col) - min(var_col);
                    mean_val = mean(var_col);

                    % 敏感度 = 变化范围 / 平均值（归一化）
                    if mean_val ~= 0
                        sensitivity_score = (var_range / abs(mean_val));
                    else
                        sensitivity_score = var_range;
                    end

                    sensitivity.variableSensitivity(i).index = i;
                    sensitivity.variableSensitivity(i).score = sensitivity_score;
                    sensitivity.variableSensitivity(i).range = var_range;

                    sensitivity_scores(i) = sensitivity_score;
                end

                % 排序敏感度指标
                [~, idx] = sort(sensitivity_scores, 'descend');
                sensitivity.rankedIndices = idx;
                sensitivity.topInfluencingVariables = idx(1:min(3, length(idx)));
            end

            sensitivity.status = 'completed';
        end

        function tradeoff = tradeoffAnalysis(obj, results)
            % tradeoffAnalysis 目标权衡分析
            %
            % 输入:
            %   results - 优化结果struct
            %
            % 输出:
            %   tradeoff - 权衡分析结果struct

            tradeoff = struct();

            if ~isfield(results, 'paretoFront') || size(results.paretoFront, 2) < 2
                tradeoff.status = 'unavailable';
                tradeoff.message = '需要至少2个目标来进行权衡分析';
                return;
            end

            front = results.paretoFront;
            nObjs = size(front, 2);

            % 计算目标对间的相关性
            correlationMatrix = corrcoef(front);
            tradeoff.objectiveCorrelation = correlationMatrix;

            % 识别主要权衡关系
            tradeoff_pairs = {};
            for i = 1:nObjs
                for j = i+1:nObjs
                    corr_val = correlationMatrix(i, j);

                    % 负相关表示权衡
                    if corr_val < -0.5
                        tradeoff_pairs{end+1} = struct( ...
                            'objective1', i, ...
                            'objective2', j, ...
                            'correlation', corr_val, ...
                            'tradeoffStrength', abs(corr_val));
                    end
                end
            end

            tradeoff.tradeoffPairs = tradeoff_pairs;
            tradeoff.numberOfTradeoffs = length(tradeoff_pairs);
            tradeoff.status = 'completed';
        end

        function recommendation = recommendSolution(obj, results, preference)
            % recommendSolution 推荐最优解
            %
            % 输入:
            %   results - 优化结果struct
            %   preference - 可选，用户偏好struct
            %
            % 输出:
            %   recommendation - 推荐解struct

            recommendation = struct();

            if ~isfield(results, 'paretoFront') || isempty(results.paretoFront)
                recommendation.status = 'failed';
                recommendation.message = 'Pareto前沿为空';
                return;
            end

            front = results.paretoFront;

            % 如果没有偏好，使用TOPSIS方法选择compromise解
            if nargin < 3
                recommendation = obj.selectCompromiseSolution(front);
            else
                recommendation = obj.selectSolutionByPreference(front, preference);
            end

            % 添加额外信息
            recommendation.paretoFrontSize = size(front, 1);
            recommendation.objectiveCount = size(front, 2);
        end

        function exportAnalysisReport(obj, results, filePath)
            % exportAnalysisReport 导出分析报告
            %
            % 输入:
            %   results - 优化结果struct
            %   filePath - 报告文件路径

            try
                fid = fopen(filePath, 'w');

                fprintf(fid, '=== MAPO 优化结果分析报告 ===\n\n');

                % Pareto前沿分析
                stats = obj.analyzeParetoFront(results);
                fprintf(fid, '1. Pareto前沿分析\n');
                fprintf(fid, '   - 解的个数: %d\n', stats.solutionCount);
                fprintf(fid, '   - 目标数: %d\n', stats.objectiveCount);

                % 敏感性分析
                fprintf(fid, '\n2. 敏感性分析\n');
                sensitivity = obj.sensitivityAnalysis(results);
                if isfield(sensitivity, 'topInfluencingVariables')
                    fprintf(fid, '   - 最有影响的变量索引: %s\n', ...
                        sprintf('%d ', sensitivity.topInfluencingVariables));
                end

                % 推荐解
                fprintf(fid, '\n3. 推荐解\n');
                recommendation = obj.recommendSolution(results);
                fprintf(fid, '   - 推荐指标索引: %d\n', recommendation.index);
                if isfield(recommendation, 'objectives')
                    fprintf(fid, '   - 目标值: %s\n', ...
                        sprintf('%.6e ', recommendation.objectives));
                end

                fprintf(fid, '\n报告生成时间: %s\n', datetime('now'));

                fclose(fid);
            catch ME
                warning('ResultsAnalyzer:ExportFailed', '报告导出失败: %s', ME.message);
            end
        end
    end

    methods (Access = private)
        function quality = calculateConvergenceQuality(~, front)
            % calculateConvergenceQuality 计算收敛质量

            if size(front, 1) < 2
                quality = 1.0;
                return;
            end

            % 简化指标：目标值范围
            ranges = [];
            for i = 1:size(front, 2)
                col = front(:, i);
                col = col(isfinite(col));
                if ~isempty(col)
                    ranges(i) = (max(col) - min(col)) / (abs(mean(col)) + eps);
                end
            end

            quality = 1 / (1 + mean(ranges));  % 归一化到[0,1]
        end

        function recommendation = selectCompromiseSolution(~, front)
            % selectCompromiseSolution 使用TOPSIS选择compromise解

            recommendation = struct();

            % 归一化前沿
            normalized = front ./ repmat(max(abs(front), [], 1), size(front, 1), 1);

            % 计算到理想点的距离
            ideal = ones(1, size(normalized, 2));
            distances = sqrt(sum((normalized - repmat(ideal, size(normalized, 1), 1)).^2, 2));

            % 选择最接近理想的解
            [~, idx] = min(distances);

            recommendation.index = idx;
            recommendation.objectives = front(idx, :);
            recommendation.score = 1 - (distances(idx) / max(distances));
        end

        function recommendation = selectSolutionByPreference(~, front, preference)
            % selectSolutionByPreference 根据偏好选择解

            recommendation = struct();

            if ~isfield(preference, 'weights')
                % 无权重，使用compromise解
                recommendation = selectCompromiseSolution(~, front);
                return;
            end

            % 加权计分
            weights = preference.weights;
            if length(weights) ~= size(front, 2)
                error('ResultsAnalyzer:InvalidWeights', '权重数与目标数不匹配');
            end

            scores = front * weights(:);
            [~, idx] = min(scores);  % 假设最小化

            recommendation.index = idx;
            recommendation.objectives = front(idx, :);
            recommendation.weightedScore = scores(idx);
        end
    end
end
