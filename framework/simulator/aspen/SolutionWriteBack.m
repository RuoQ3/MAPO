classdef SolutionWriteBack < handle
    % SolutionWriteBack 方案回写Aspen验证
    %
    % 功能:
    %   - 将优化方案写入Aspen模型
    %   - 运行Aspen仿真验证结果
    %   - 生成验证报告
    %   - 导出生产配置
    %
    % 示例:
    %   writeBack = SolutionWriteBack(simulator, treeBrowser);
    %   writeBack.setSolution(optimalVars, varMapping);
    %   report = writeBack.writeBackAndSimulate();

    properties (Access = private)
        simulator          % Simulator对象
        treeBrowser        % AspenTreeBrowser对象
        currentSolution    % 当前设置的方案
        variableMapping    % 变量到节点路径的映射
        verificationResult % 验证结果
        expectedObjectives % 预期目标值（来自优化结果）
        logger             % Logger实例
    end

    methods
        function obj = SolutionWriteBack(simulator, treeBrowser)
            % SolutionWriteBack 构造函数
            %
            % 输入:
            %   simulator - Simulator对象
            %   treeBrowser - AspenTreeBrowser对象

            obj.simulator = simulator;
            if nargin >= 2
                obj.treeBrowser = treeBrowser;
            else
                obj.treeBrowser = [];
            end
            obj.currentSolution = [];
            obj.variableMapping = struct();
            obj.verificationResult = [];
            obj.expectedObjectives = [];

            if exist('Logger', 'class')
                obj.logger = Logger.getLogger('SolutionWriteBack');
            else
                obj.logger = [];
            end
        end

        function setSolution(obj, variableValues, variableNames, variableMapping)
            % setSolution 设置要回写的优化方案
            %
            % 输入:
            %   variableValues - 优化变量值向量
            %   variableNames - 变量名称cell数组
            %   variableMapping - 变量到Aspen节点路径的映射struct
            %
            % 例:
            %   writeBack.setSolution([100, 200, 300], {'x1', 'x2', 'x3'}, mapping);

            obj.currentSolution = struct();
            obj.currentSolution.values = variableValues;
            obj.currentSolution.names = variableNames;
            obj.currentSolution.timestamp = datetime('now');

            if nargin >= 4
                obj.variableMapping = variableMapping;
            end
        end

        function setExpectedObjectives(obj, expectedObjectives)
            % setExpectedObjectives 设置预期目标值（来自优化结果）
            %
            % 输入:
            %   expectedObjectives - 预期目标值向量
            %
            % 说明:
            %   设置后，writeBackAndSimulate会自动对比实际与预期值

            obj.expectedObjectives = expectedObjectives;
        end

        function [report, success] = writeBackAndSimulate(obj, timeout)
            % writeBackAndSimulate 将方案写回并运行仿真
            %
            % 输入:
            %   timeout - (可选) 仿真超时时间（秒）
            %
            % 输出:
            %   report - 验证报告struct
            %   success - 仿真是否成功
            %
            % 说明:
            %   将优化方案的变量值写入Aspen模型中，运行仿真，对比结果

            report = struct();
            success = false;

            if isempty(obj.currentSolution)
                report.status = 'error';
                report.message = '未设置优化方案';
                return;
            end

            if nargin < 2
                timeout = 300;  % 默认5分钟超时
            end

            try
                % 第一步：写入变量值
                obj.writeVariablesToAspen();

                % 第二步：运行仿真
                [simSuccess, simTime] = obj.runAspenSimulation(timeout);

                % 第三步：验证结果
                report = obj.verifySimulationResults(simSuccess, simTime);
                success = simSuccess;

                obj.verificationResult = report;

            catch ME
                report.status = 'error';
                report.message = sprintf('回写失败: %s', ME.message);
                success = false;
            end
        end

        function report = generateVerificationReport(obj)
            % generateVerificationReport 生成详细的验证报告

            if isempty(obj.verificationResult)
                report.status = 'unavailable';
                report.message = '未执行过验证';
                return;
            end

            report = obj.verificationResult;

            % 添加建议和分析
            report.analysis = struct();

            if report.success
                % 计算与预期的偏差
                if isfield(report, 'expectedObjectives') && isfield(report, 'actualObjectives')
                    deviations = abs(report.actualObjectives - report.expectedObjectives) ./ ...
                                 (abs(report.expectedObjectives) + eps);
                    report.analysis.deviations = deviations;
                    report.analysis.maxDeviation = max(deviations);
                    report.analysis.meanDeviation = mean(deviations);

                    if report.analysis.maxDeviation > 0.1
                        report.analysis.warning = '与预期结果偏差较大，可能需要重新优化';
                    else
                        report.analysis.status = '验证成功，结果精度良好';
                    end
                end
            else
                report.analysis.status = '仿真失败，建议检查模型配置';
            end
        end

        function productionConfig = generateProductionConfig(obj)
            % generateProductionConfig 生成生产配置文件
            %
            % 输出:
            %   productionConfig - 生产配置struct，包含所有设置参数

            productionConfig = struct();

            if isempty(obj.currentSolution)
                productionConfig.status = 'error';
                return;
            end

            productionConfig.timestamp = obj.currentSolution.timestamp;
            productionConfig.solution = obj.currentSolution;

            if ~isempty(obj.verificationResult)
                productionConfig.verificationStatus = obj.verificationResult.status;
                if isfield(obj.verificationResult, 'actualObjectives')
                    productionConfig.achievedObjectives = obj.verificationResult.actualObjectives;
                end
            end

            % 格式化为易于使用的形式
            productionConfig.variableAssignments = struct();
            for i = 1:length(obj.currentSolution.names)
                varName = obj.currentSolution.names{i};
                value = obj.currentSolution.values(i);
                productionConfig.variableAssignments.(varName) = value;
            end

            productionConfig.status = 'ready';
        end

        function exportProductionConfigToFile(obj, filePath)
            % exportProductionConfigToFile 将生产配置导出为JSON文件
            %
            % 输入:
            %   filePath - JSON文件路径

            try
                config = obj.generateProductionConfig();

                % 转换为JSON并保存
                jsonText = jsonencode(config);

                fid = fopen(filePath, 'w');
                fprintf(fid, jsonText);
                fclose(fid);

            catch ME
                error('SolutionWriteBack:ExportFailed', '配置导出失败: %s', ME.message);
            end
        end

        function exportVerificationReportToFile(obj, filePath)
            % exportVerificationReportToFile 将验证报告导出为文本文件
            %
            % 输入:
            %   filePath - 文本文件路径

            try
                report = obj.generateVerificationReport();

                fid = fopen(filePath, 'w');

                fprintf(fid, '=== Aspen方案验证报告 ===\n\n');
                fprintf(fid, '生成时间: %s\n\n', datetime('now'));

                fprintf(fid, '1. 方案信息\n');
                if isfield(report, 'solutionTimestamp')
                    fprintf(fid, '   优化时间: %s\n', report.solutionTimestamp);
                end

                fprintf(fid, '\n2. 变量设置\n');
                if ~isempty(obj.currentSolution)
                    for i = 1:length(obj.currentSolution.names)
                        fprintf(fid, '   %s = %.6g\n', ...
                            obj.currentSolution.names{i}, ...
                            obj.currentSolution.values(i));
                    end
                end

                fprintf(fid, '\n3. 仿真结果\n');
                fprintf(fid, '   状态: %s\n', report.status);
                if isfield(report, 'actualObjectives')
                    fprintf(fid, '   目标值: %s\n', sprintf('%.6e ', report.actualObjectives));
                end
                if isfield(report, 'simulationTime')
                    fprintf(fid, '   仿真耗时: %.2f秒\n', report.simulationTime);
                end

                fprintf(fid, '\n4. 验证分析\n');
                if isfield(report, 'analysis')
                    if isfield(report.analysis, 'status')
                        fprintf(fid, '   %s\n', report.analysis.status);
                    end
                    if isfield(report.analysis, 'warning')
                        fprintf(fid, '   警告: %s\n', report.analysis.warning);
                    end
                end

                fclose(fid);

            catch ME
                error('SolutionWriteBack:ExportFailed', '报告导出失败: %s', ME.message);
            end
        end

        function result = getVerificationResult(obj)
            % getVerificationResult 获取最后的验证结果

            result = obj.verificationResult;
        end
    end

    methods (Access = private)
        function writeVariablesToAspen(obj)
            % writeVariablesToAspen 将变量值写入Aspen

            if isempty(obj.simulator)
                error('SolutionWriteBack:NoSimulator', '未设置仿真器');
            end

            % 将变量值通过仿真器设置到Aspen
            obj.simulator.setVariables(obj.currentSolution.values);
        end

        function [success, simulationTime] = runAspenSimulation(obj, timeout)
            % runAspenSimulation 运行Aspen仿真

            tic;

            try
                success = obj.simulator.run(timeout);
                simulationTime = toc;
            catch ME
                simulationTime = toc;
                success = false;
            end
        end

        function report = verifySimulationResults(obj, simSuccess, simTime)
            % verifySimulationResults 验证仿真结果

            report = struct();
            report.status = 'unknown';
            report.simulationSuccess = simSuccess;
            report.simulationTime = simTime;

            if simSuccess
                try
                    % 获取仿真结果
                    results = obj.simulator.getResults();

                    report.status = 'success';
                    report.actualObjectives = results.objectives;
                    if isfield(results, 'constraints')
                        report.actualConstraints = results.constraints;
                    end

                    % 对比预期结果
                    if ~isempty(obj.expectedObjectives)
                        report.expectedObjectives = obj.expectedObjectives;

                        % 计算偏差
                        deviations = abs(report.actualObjectives - obj.expectedObjectives) ./ ...
                                     (abs(obj.expectedObjectives) + eps);
                        report.deviations = deviations;
                        report.maxDeviation = max(deviations);
                        report.meanDeviation = mean(deviations);

                        % 容差判断
                        tolerance = 0.05; % 5%
                        report.withinTolerance = all(deviations < tolerance);

                        obj.logMsg('info', sprintf('验证偏差: 最大 %.2f%%, 平均 %.2f%%', ...
                            report.maxDeviation * 100, report.meanDeviation * 100));
                    end

                    report.message = '仿真成功，结果已获取';
                    obj.logMsg('info', '方案回写验证成功');

                catch ME
                    report.status = 'partial_success';
                    report.message = sprintf('仿真运行成功但结果获取失败: %s', ME.message);
                    obj.logMsg('warning', report.message);
                end
            else
                report.status = 'failed';
                report.message = '仿真执行失败';
                obj.logMsg('error', '方案回写仿真失败');
            end

            report.timestamp = datetime('now');
        end

        function logMsg(obj, level, message)
            % logMsg 统一日志输出

            if ~isempty(obj.logger)
                switch lower(level)
                    case 'info'
                        obj.logger.info(message);
                    case 'warning'
                        obj.logger.warning(message);
                    case 'error'
                        obj.logger.error(message);
                end
            end
        end
    end
end
