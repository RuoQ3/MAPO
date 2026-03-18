classdef (Abstract) AlgorithmBase < IOptimizer
    % AlgorithmBase 优化算法抽象基类
    % 继承IOptimizer接口，提供算法的通用功能实现
    %
    % 功能:
    %   - 日志记录集成
    %   - 停止条件检查
    %   - 评估计数和时间统计
    %   - 历史记录管理
    %   - 进度显示
    %   - Protected辅助方法
    %
    % 使用方法:
    %   具体算法继承此基类，只需实现optimize()方法
    %
    % 示例:
    %   classdef MyAlgorithm < AlgorithmBase
    %       methods
    %           function results = optimize(obj, problem, config)
    %               obj.initialize(problem, config);
    %
    %               while ~obj.shouldStop()
    %                   % 执行迭代
    %                   obj.incrementEvaluationCount(popSize);
    %                   obj.logIteration(iter, data);
    %               end
    %
    %               results = obj.finalizeResults();
    %           end
    %       end
    %   end


    properties (Access = protected)
        logger;              % Logger对象
        maxEvaluations;      % 最大评估次数
        maxTime;             % 最大运行时间（秒）
        targetObjective;     % 目标值（用于提前终止）
        verbose;             % 是否显示详细信息
        history;             % 历史记录结构体数组
        currentIteration;    % 当前迭代次数
        population;          % 当前种群（Population对象）
        bestIndividual;      % 当前最优个体
    end

    methods
        function obj = AlgorithmBase()
            % AlgorithmBase 构造函数
            %
            % 示例:
            %   algorithm = MyAlgorithm();

            % 调用父类构造函数
            obj@IOptimizer();

            % 初始化属性
            obj.logger = [];
            obj.maxEvaluations = 10000;
            obj.maxTime = inf;
            obj.targetObjective = [];
            obj.verbose = true;
            obj.history = struct([]);
            obj.currentIteration = 0;
            obj.population = [];
            obj.bestIndividual = [];
        end

        function setLogger(obj, logger)
            % setLogger 设置日志器
            %
            % 输入:
            %   logger - Logger对象
            %
            % 示例:
            %   logger = Logger(Logger.INFO, 'algorithm.log');
            %   algorithm.setLogger(logger);

            if isa(logger, 'Logger')
                obj.logger = logger;
            else
                warning('AlgorithmBase:InvalidLogger', '输入必须是Logger对象');
            end
        end

        function setMaxEvaluations(obj, maxEvals)
            % setMaxEvaluations 设置最大评估次数
            %
            % 输入:
            %   maxEvals - 最大评估次数
            %
            % 示例:
            %   algorithm.setMaxEvaluations(50000);

            obj.maxEvaluations = maxEvals;
        end

        function setMaxTime(obj, maxTime)
            % setMaxTime 设置最大运行时间
            %
            % 输入:
            %   maxTime - 最大时间（秒）
            %
            % 示例:
            %   algorithm.setMaxTime(3600); % 1小时

            obj.maxTime = maxTime;
        end

        function setTargetObjective(obj, target)
            % setTargetObjective 设置目标值（提前终止条件）
            %
            % 输入:
            %   target - 目标值向量
            %
            % 说明:
            %   当找到比目标更好的解时，算法可以提前终止
            %
            % 示例:
            %   algorithm.setTargetObjective([0.0, 0.0]);

            obj.targetObjective = target;
        end

        function setVerbose(obj, verbose)
            % setVerbose 设置是否显示详细信息
            %
            % 输入:
            %   verbose - 布尔值
            %
            % 示例:
            %   algorithm.setVerbose(false);

            obj.verbose = verbose;
        end

        function hist = getHistory(obj)
            % getHistory 获取历史记录
            %
            % 输出:
            %   hist - 历史记录结构体数组
            %
            % 示例:
            %   history = algorithm.getHistory();

            hist = obj.history;
        end

        function pop = getPopulation(obj)
            % getPopulation 获取当前种群
            %
            % 输出:
            %   pop - Population对象
            %
            % 示例:
            %   population = algorithm.getPopulation();

            pop = obj.population;
        end

        function best = getBestIndividual(obj)
            % getBestIndividual 获取当前最优个体
            %
            % 输出:
            %   best - Individual对象
            %
            % 示例:
            %   bestInd = algorithm.getBestIndividual();

            best = obj.bestIndividual;
        end

        function stop(obj)
            % stop 停止算法执行（实现IOptimizer接口）
            %
            % 示例:
            %   algorithm.stop();

            if obj.running
                obj.setStopped(true);
                obj.setRunning(false);
                obj.logMessage('INFO', '算法已被手动停止');
            end
        end

        function reset(obj)
            % reset 重置算法状态（覆盖父类方法）
            %
            % 示例:
            %   algorithm.reset();

            % 调用父类reset
            reset@IOptimizer(obj);

            % 重置额外属性
            obj.history = struct([]);
            obj.currentIteration = 0;
            obj.population = [];
            obj.bestIndividual = [];
        end
    end

    methods (Access = protected)
        function initialize(obj, problem, config)
            % initialize 初始化算法
            %
            % 输入:
            %   problem - OptimizationProblem对象
            %   config - 配置对象或结构体
            %
            % 说明:
            %   子类应在optimize()开始时调用此方法

            obj.problem = problem;
            obj.config = config;
            obj.setRunning(true);
            obj.setStopped(false);
            obj.setCompleted(false);
            obj.currentIteration = 0;
            obj.evaluationCount = 0;
            obj.startTime = tic;
            obj.history = struct([]);

            % 从配置中读取参数
            if isstruct(config)
                if isfield(config, 'maxEvaluations')
                    obj.maxEvaluations = config.maxEvaluations;
                end
                if isfield(config, 'maxTime')
                    obj.maxTime = config.maxTime;
                end
                if isfield(config, 'targetObjective')
                    obj.targetObjective = config.targetObjective;
                end
                if isfield(config, 'verbose')
                    obj.verbose = config.verbose;
                end
            end

            obj.logMessage('INFO', '========================================');
            obj.logMessage('INFO', '开始优化: %s', problem.name);
            obj.logMessage('INFO', '算法: %s', class(obj));
            obj.logMessage('INFO', '变量数: %d', problem.getNumberOfVariables());
            obj.logMessage('INFO', '目标数: %d', problem.getNumberOfObjectives());
            obj.logMessage('INFO', '约束数: %d', problem.getNumberOfConstraints());
            obj.logMessage('INFO', '最大评估次数: %d', obj.maxEvaluations);
            obj.logMessage('INFO', '最大运行时间: %.1f秒', obj.maxTime);
            obj.logMessage('INFO', '========================================');
        end

        function tf = shouldStop(obj)
            % shouldStop 检查是否应该停止
            %
            % 输出:
            %   tf - 布尔值
            %
            % 说明:
            %   子类在每次迭代时调用此方法检查停止条件

            tf = false;

            % 检查手动停止
            if obj.stopped
                obj.logMessage('INFO', '检测到停止信号');
                tf = true;
                return;
            end

            % 检查最大评估次数
            if obj.evaluationCount >= obj.maxEvaluations
                obj.logMessage('INFO', '达到最大评估次数: %d', obj.evaluationCount);
                tf = true;
                return;
            end

            % 检查最大运行时间
            elapsed = toc(obj.startTime);
            if elapsed >= obj.maxTime
                obj.logMessage('INFO', '达到最大运行时间: %.2f秒', elapsed);
                tf = true;
                return;
            end

            % 检查目标值
            if ~isempty(obj.targetObjective) && ~isempty(obj.bestIndividual)
                if obj.hasReachedTarget()
                    obj.logMessage('INFO', '达到目标值');
                    tf = true;
                    return;
                end
            end
        end

        function tf = hasReachedTarget(obj)
            % hasReachedTarget 检查是否达到目标值
            %
            % 输出:
            %   tf - 布尔值
            %
            % 说明:
            %   比较最优个体的目标值与目标值

            tf = false;
            if isempty(obj.bestIndividual) || isempty(obj.targetObjective)
                return;
            end

            bestObjs = obj.bestIndividual.getObjectives();
            if length(bestObjs) ~= length(obj.targetObjective)
                return;
            end

            % 检查是否所有目标都达到或优于目标值
            tf = all(bestObjs <= obj.targetObjective);
        end

        function results = finalizeResults(obj)
            % finalizeResults 完成优化并生成结果
            %
            % 输出:
            %   results - 结果结构体
            %
            % 说明:
            %   子类应在optimize()结束时调用此方法

            obj.setRunning(false);
            obj.setCompleted(true);
            obj.endTime = toc(obj.startTime);

            % 构建结果
            results = struct();
            results.problem = obj.problem.name;
            results.algorithm = class(obj);
            results.evaluations = obj.evaluationCount;
            results.iterations = obj.currentIteration;
            results.elapsedTime = obj.endTime;
            results.stopped = obj.stopped;

            % 保存种群和最优解
            if ~isempty(obj.population)
                results.population = obj.population;
                results.paretoFront = obj.population.getParetoFront();
            else
                results.population = [];
                results.paretoFront = [];
            end

            if ~isempty(obj.bestIndividual)
                results.bestSolution = obj.bestIndividual.getVariables();
                results.bestObjectives = obj.bestIndividual.getObjectives();
                results.bestFeasible = obj.bestIndividual.isFeasible();
            else
                results.bestSolution = [];
                results.bestObjectives = [];
                results.bestFeasible = false;
            end

            % 保存历史记录
            results.history = obj.history;

            % 存储结果
            obj.results = results;
            obj.bestSolution = results.bestSolution;

            % 调用算法结束回调
            obj.callAlgorithmEndCallback(results);

            % 日志
            obj.logMessage('INFO', '========================================');
            obj.logMessage('INFO', '优化完成');
            obj.logMessage('INFO', '总评估次数: %d', obj.evaluationCount);
            obj.logMessage('INFO', '总迭代次数: %d', obj.currentIteration);
            obj.logMessage('INFO', '运行时间: %.2f秒', obj.endTime);
            if ~isempty(obj.bestIndividual)
                obj.logMessage('INFO', '最优目标值: [%s]', ...
                              num2str(obj.bestIndividual.getObjectives(), '%.6g '));
                obj.logMessage('INFO', '最优解可行: %s', mat2str(obj.bestIndividual.isFeasible()));
            end
            obj.logMessage('INFO', '========================================');
        end

        function updateBestIndividual(obj, individual)
            % updateBestIndividual 更新最优个体
            %
            % 输入:
            %   individual - Individual对象
            %
            % 说明:
            %   子类在找到更好的解时调用此方法

            if isempty(obj.bestIndividual)
                obj.bestIndividual = individual.clone();
            else
                % 比较并更新
                if individual.dominates(obj.bestIndividual)
                    obj.bestIndividual = individual.clone();
                elseif obj.problem.getNumberOfObjectives() == 1
                    % 单目标：直接比较目标值
                    if individual.getObjective(1) < obj.bestIndividual.getObjective(1)
                        obj.bestIndividual = individual.clone();
                    end
                end
            end
        end

        function updateBestFromPopulation(obj, population)
            % updateBestFromPopulation 从种群中更新最优个体
            %
            % 输入:
            %   population - Population对象
            %
            % 说明:
            %   为单目标优化选择最优个体
            %   为多目标优化选择Pareto前沿中的代表解

            if population.isEmpty()
                return;
            end

            if obj.problem.getNumberOfObjectives() == 1
                % 单目标：选择目标值最小的
                individuals = population.getAll();
                bestIdx = 1;
                bestObj = individuals(1).getObjective(1);

                for i = 2:length(individuals)
                    objVal = individuals(i).getObjective(1);
                    if objVal < bestObj
                        bestObj = objVal;
                        bestIdx = i;
                    end
                end

                obj.updateBestIndividual(individuals(bestIdx));
            else
                % 多目标：从Pareto前沿中选择（这里选择第一个）
                front = population.getParetoFront();
                if ~front.isEmpty()
                    obj.updateBestIndividual(front.get(1));
                end
            end
        end

        function logIteration(obj, iteration, data)
            % logIteration 记录迭代信息
            %
            % 输入:
            %   iteration - 迭代次数
            %   data - 迭代数据（结构体）
            %
            % 说明:
            %   子类在每次迭代结束时调用此方法

            obj.currentIteration = iteration;

            % 保存历史记录
            if ~isempty(data)
                if isempty(obj.history)
                    obj.history = data;
                else
                    obj.history(end+1) = data;
                end
            end

            % 显示进度
            if obj.verbose && mod(iteration, 10) == 0
                elapsed = toc(obj.startTime);
                if ~isempty(obj.bestIndividual)
                    obj.logMessage('INFO', 'Iter %d | Evals: %d | Time: %.2fs | Best: [%s]', ...
                                  iteration, obj.evaluationCount, elapsed, ...
                                  num2str(obj.bestIndividual.getObjectives(), '%.6g '));
                else
                    obj.logMessage('INFO', 'Iter %d | Evals: %d | Time: %.2fs', ...
                                  iteration, obj.evaluationCount, elapsed);
                end
            end

            % 调用迭代回调
            obj.callIterationCallback(iteration, data);
        end

        function logMessage(obj, level, message, varargin)
            % logMessage 记录日志消息
            %
            % 输入:
            %   level - 日志级别 ('DEBUG', 'INFO', 'WARNING', 'ERROR')
            %   message - 消息字符串（支持sprintf格式）
            %   varargin - 格式化参数
            %
            % 说明:
            %   如果设置了logger，使用logger记录
            %   否则，根据级别输出到控制台

            % 格式化消息
            if ~isempty(varargin)
                message = sprintf(message, varargin{:});
            end

            % 使用logger
            if ~isempty(obj.logger)
                switch upper(level)
                    case 'DEBUG'
                        obj.logger.debug(message);
                    case 'INFO'
                        obj.logger.info(message);
                    case 'WARNING'
                        obj.logger.warning(message);
                    case 'ERROR'
                        obj.logger.error(message);
                    otherwise
                        obj.logger.info(message);
                end
            else
                % 如果verbose，输出到控制台
                if obj.verbose
                    switch upper(level)
                        case {'ERROR', 'WARNING'}
                            fprintf('[%s] %s\n', level, message);
                        case 'INFO'
                            fprintf('%s\n', message);
                        % DEBUG级别不输出到控制台（除非有logger）
                    end
                end
            end
        end

        function validateProblem(obj)
            % validateProblem 验证问题定义
            %
            % 说明:
            %   检查问题是否完整定义
            %   子类可以覆盖此方法添加特定检查

            if isempty(obj.problem)
                error('AlgorithmBase:NoProblem', '未设置优化问题');
            end

            if obj.problem.getNumberOfVariables() == 0
                error('AlgorithmBase:NoVariables', '问题未定义变量');
            end

            if obj.problem.getNumberOfObjectives() == 0
                error('AlgorithmBase:NoObjectives', '问题未定义目标');
            end
        end

        function validateConfig(obj)
            % validateConfig 验证算法配置
            %
            % 说明:
            %   检查配置参数是否有效
            %   子类应该覆盖此方法添加特定参数检查

            if obj.maxEvaluations <= 0
                error('AlgorithmBase:InvalidConfig', '最大评估次数必须大于0');
            end

            if obj.maxTime <= 0
                obj.maxTime = inf; % 默认无时间限制
            end
        end

        function displayProgress(obj, iteration)
            % displayProgress 显示进度条或进度信息
            %
            % 输入:
            %   iteration - 当前迭代次数
            %
            % 说明:
            %   子类可以调用此方法显示自定义进度

            if ~obj.verbose
                return;
            end

            elapsed = toc(obj.startTime);
            progress = obj.evaluationCount / obj.maxEvaluations * 100;

            fprintf('Iteration %d | Progress: %.1f%% | Evaluations: %d/%d | Time: %.1fs\n', ...
                    iteration, progress, obj.evaluationCount, obj.maxEvaluations, elapsed);
        end

        function variables = repairVariables(obj, variables)
            % repairVariables 修复变量值以符合非连续类型约束
            %
            % 输入:
            %   variables - 变量值向量 [1×n]
            %
            % 输出:
            %   variables - 修复后的变量值向量
            %
            % 说明:
            %   对整数变量进行圆整
            %   对离散/分类变量映射到最近的有效值
            %   对连续变量保持不变
            %
            % 示例:
            %   repaired = obj.repairVariables([3.7, 1.3, 2.9]);

            if isempty(obj.problem)
                return;
            end

            variableSet = obj.problem.getVariableSet();
            if isempty(variableSet)
                return;
            end

            vars = variableSet.getIterator();
            if length(vars) ~= length(variables)
                error('AlgorithmBase:VariableSizeMismatch', ...
                      '变量数量不匹配: 期望%d, 实际%d', length(vars), length(variables));
            end

            % 对每个变量进行修复
            for i = 1:length(vars)
                var = vars{i};
                value = variables(i);

                % 使用 denormalize 方法来处理各种类型的变量
                % 先将值归一化再反归一化，这样可以自动处理所有类型
                try
                    % 对整数变量：四舍五入到整数
                    if strcmp(var.type, 'integer')
                        value = round(value);
                        % 确保在边界内
                        value = max(var.lowerBound, min(var.upperBound, value));
                    % 对离散和分类变量：映射到最近的有效值
                    elseif strcmp(var.type, 'discrete') || strcmp(var.type, 'categorical')
                        % 计算归一化值，然后通过 denormalize 映射到有效值
                        % 首先尝试找到该值在允许值中的索引
                        values = var.values;
                        if ~isempty(values)
                            % 计算与所有允许值的距离
                            if isnumeric(value) && iscell(values) && isnumeric(values{1})
                                % 离散数值变量
                                distances = cellfun(@(v) abs(v - value), values);
                                [~, idx] = min(distances);
                                value = values{idx};
                            elseif ischar(value) || isstring(value)
                                % 分类变量：精确匹配或返回第一个值
                                value = char(value);
                                found = false;
                                for j = 1:length(values)
                                    if ischar(values{j}) && strcmp(value, values{j})
                                        found = true;
                                        break;
                                    end
                                end
                                if ~found
                                    % 如果找不到精确匹配，使用第一个值
                                    value = values{1};
                                end
                            else
                                % 其他情况：使用映射到最近的有效值的逻辑
                                n = length(values);
                                % 先转换到 [0, 1]，再映射
                                if isnumeric(values{1})
                                    minVal = min(cellfun(@(v) v, values));
                                    maxVal = max(cellfun(@(v) v, values));
                                    if maxVal > minVal
                                        normalized = (value - minVal) / (maxVal - minVal);
                                        normalized = max(0, min(1, normalized));
                                        idx = round(normalized * (n - 1)) + 1;
                                        idx = max(1, min(n, idx));
                                        value = values{idx};
                                    else
                                        value = values{1};
                                    end
                                else
                                    % 无法确定数值映射，使用第一个值
                                    value = values{1};
                                end
                            end
                        end
                    % 对连续变量：确保在边界内
                    elseif strcmp(var.type, 'continuous')
                        if ~isempty(var.lowerBound) && ~isempty(var.upperBound)
                            value = max(var.lowerBound, min(var.upperBound, value));
                        end
                    end
                catch
                    % 如果出错，尝试保持原值但确保在边界内
                    if ~isempty(var.lowerBound) && ~isempty(var.upperBound)
                        value = max(var.lowerBound, min(var.upperBound, value));
                    end
                end

                variables(i) = value;
            end
        end

        function data = getIterationData(obj, iteration)
            % getIterationData 获取用于GUI/日志的迭代数据（通用实现）
            %
            % 输入:
            %   iteration - 迭代次数
            %
            % 输出:
            %   data - struct包含：
            %     - iteration: 迭代号
            %     - evaluations: 评估次数
            %     - bestObjectives: 当前最优目标值
            %     - paretoFront: Pareto前沿目标值矩阵 (nSolutions x nObj)
            %     - populationObjectives: 全种群目标值矩阵 (nInds x nObj)
            %     - archiveSize: Pareto解数量
            %     - feasibleRatio: 可行解比例（可选）
            %
            % 说明:
            %   通用的迭代数据提取方法，子类可覆盖以添加特定信息

            data = struct();
            data.iteration = iteration;
            data.evaluations = obj.evaluationCount;
            data.bestObjectives = [];
            data.paretoFront = [];
            data.populationObjectives = [];
            data.archiveSize = 0;

            if isempty(obj.population)
                return;
            end

            inds = obj.population.getAll();
            if isempty(inds)
                return;
            end

            % 尝试使用已计算的rank提取第一前沿，避免重复fastNonDominatedSort
            frontInds = Individual.empty(0, 0);
            try
                for i = 1:length(inds)
                    if inds(i).getRank() == 1
                        frontInds(end+1) = inds(i); %#ok<AGROW>
                    end
                end
            catch
                frontInds = Individual.empty(0, 0);
            end

            if isempty(frontInds)
                frontInds = inds;
            end

            % 提取目标值矩阵
            nSolutions = length(frontInds);
            if nSolutions == 0
                return;
            end

            try
                nObj = length(frontInds(1).getObjectives());
            catch
                nObj = 0;
            end
            if nObj <= 0
                return;
            end

            % 全体个体目标值（用于绘制非Pareto解）
            allObjValues = nan(length(inds), nObj);
            for i = 1:length(inds)
                try
                    allObjValues(i, :) = inds(i).getObjectives();
                catch
                end
            end

            validAll = ~all(isnan(allObjValues), 2);
            allObjValues = allObjValues(validAll, :);
            data.populationObjectives = allObjValues;

            objValues = nan(nSolutions, nObj);
            for i = 1:nSolutions
                try
                    objValues(i, :) = frontInds(i).getObjectives();
                catch
                end
            end

            % 删除全NaN行（防御）
            validRow = ~all(isnan(objValues), 2);
            objValues = objValues(validRow, :);

            data.paretoFront = objValues;
            data.archiveSize = size(objValues, 1);

            % 用每个目标的当前最小值作为"bestObjectives"，用于收敛曲线（忽略NaN/Inf）
            best = nan(1, nObj);
            if ~isempty(allObjValues)
                for j = 1:nObj
                    col = allObjValues(:, j);
                    col = col(isfinite(col));
                    if ~isempty(col)
                        best(j) = min(col);
                    end
                end
            end
            if ~all(isnan(best))
                data.bestObjectives = best;
            end

            % 可行解比例（如果有约束）
            try
                if ~isempty(obj.problem) && obj.problem.getNumberOfConstraints() > 0
                    feasibleCount = 0;
                    for i = 1:length(inds)
                        try
                            if inds(i).isFeasible()
                                feasibleCount = feasibleCount + 1;
                            end
                        catch
                        end
                    end
                    data.feasibleRatio = feasibleCount / max(1, length(inds));
                end
            catch
            end
        end
    end

    methods (Static)
        function type = getAlgorithmType()
            % getAlgorithmType 获取算法类型
            %
            % 输出:
            %   type - 算法类型字符串
            %
            % 说明:
            %   子类应覆盖此方法返回具体类型

            type = 'Base';
        end
    end
end
