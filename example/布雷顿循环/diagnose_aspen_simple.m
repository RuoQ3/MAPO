% diagnose_aspen_simple.m - 简化版Aspen节点诊断工具
% 直接使用COM接口，不依赖AspenPlusSimulator类的方法

clear;
clc;

fprintf('========================================\n');
fprintf('Aspen Plus 节点诊断工具 (简化版)\n');
fprintf('========================================\n\n');

% 配置
modelPath = fullfile(pwd, '中间冷却再热布雷顿循环.bkp');

if ~exist(modelPath, 'file')
    error('模型文件不存在: %s', modelPath);
end

fprintf('模型文件: %s\n\n', modelPath);

% 直接创建COM对象
fprintf('正在连接 Aspen Plus...\n');
try
    aspenApp = actxserver('Apwn.Document');
    aspenApp.invoke('InitFromArchive2', modelPath);
    aspenApp.Visible = 1;
    aspenApp.SuppressDialogs = 1;

    % 首次运行
    fprintf('正在初始化运行...\n');
    aspenApp.Engine.Run2(1);

    % 等待完成
    while aspenApp.Engine.IsRunning == 1
        pause(2);
    end

    fprintf('连接成功！\n\n');
catch ME
    error('连接失败: %s', ME.message);
end

try
    %% 1. 列出所有流股
    fprintf('========================================\n');
    fprintf('1. 流股列表 (Streams)\n');
    fprintf('========================================\n');

    try
        streamsNode = aspenApp.Tree.FindNode('\Data\Streams');
        if ~isempty(streamsNode)
            streamCount = streamsNode.Elements.Count;
            fprintf('找到 %d 个流股:\n\n', streamCount);

            for i = 1:min(streamCount, 30)
                streamName = streamsNode.Elements.Item(i-1).Name;
                fprintf('  [%d] %s\n', i, streamName);

                % 尝试读取温度和压力
                try
                    tempPath = sprintf('\\Data\\Streams\\%s\\Input\\TEMP\\MIXED', streamName);
                    presPath = sprintf('\\Data\\Streams\\%s\\Input\\PRES\\MIXED', streamName);

                    tempNode = aspenApp.Tree.FindNode(tempPath);
                    presNode = aspenApp.Tree.FindNode(presPath);

                    if ~isempty(tempNode) && ~isempty(presNode)
                        temp = tempNode.Value;
                        pres = presNode.Value;
                        fprintf('      温度: %.2f, 压力: %.2f\n', temp, pres);
                    end
                catch
                    % 忽略
                end
            end

            if streamCount > 30
                fprintf('  ... (还有 %d 个流股未显示)\n', streamCount - 30);
            end
        else
            fprintf('未找到流股节点\n');
        end
    catch ME
        fprintf('读取流股列表失败: %s\n', ME.message);
    end

    fprintf('\n');

    %% 2. 列出所有设备
    fprintf('========================================\n');
    fprintf('2. 设备列表 (Blocks)\n');
    fprintf('========================================\n');

    try
        blocksNode = aspenApp.Tree.FindNode('\Data\Blocks');
        if ~isempty(blocksNode)
            blockCount = blocksNode.Elements.Count;
            fprintf('找到 %d 个设备:\n\n', blockCount);

            for i = 1:min(blockCount, 30)
                blockName = blocksNode.Elements.Item(i-1).Name;
                fprintf('  [%d] %s\n', i, blockName);
            end

            if blockCount > 30
                fprintf('  ... (还有 %d 个设备未显示)\n', blockCount - 30);
            end
        else
            fprintf('未找到设备节点\n');
        end
    catch ME
        fprintf('读取设备列表失败: %s\n', ME.message);
    end

    fprintf('\n');

    %% 3. 测试配置文件中的节点路径
    fprintf('========================================\n');
    fprintf('3. 测试配置文件中的节点路径\n');
    fprintf('========================================\n\n');

    configPath = fullfile(pwd, 'brayton_config.json');
    if exist(configPath, 'file')
        config = jsondecode(fileread(configPath));

        % 先收集所有节点的测试结果
        varResults = struct();
        varNames = fieldnames(config.simulator.nodeMapping.variables);

        for i = 1:length(varNames)
            varName = varNames{i};
            nodePath = config.simulator.nodeMapping.variables.(varName);
            varResults(i).name = varName;
            varResults(i).path = nodePath;
            varResults(i).valid = false;
            varResults(i).value = NaN;
            varResults(i).message = '';

            try
                node = aspenApp.Tree.FindNode(nodePath);
                if ~isempty(node) && ~strcmp(class(node), 'handle')
                    try
                        value = node.Value;
                        varResults(i).valid = true;
                        varResults(i).value = value;
                    catch ME
                        varResults(i).message = '节点存在但无法读取值';
                    end
                else
                    varResults(i).message = '节点不存在';
                end
            catch ME
                varResults(i).message = ME.message;
            end
        end

        % 收集结果节点的测试结果
        resResults = struct();
        resNames = fieldnames(config.simulator.nodeMapping.results);

        for i = 1:length(resNames)
            resName = resNames{i};
            nodePath = config.simulator.nodeMapping.results.(resName);
            resResults(i).name = resName;
            resResults(i).path = nodePath;
            resResults(i).valid = false;
            resResults(i).value = NaN;
            resResults(i).message = '';

            try
                node = aspenApp.Tree.FindNode(nodePath);
                if ~isempty(node) && ~strcmp(class(node), 'handle')
                    try
                        value = node.Value;
                        resResults(i).valid = true;
                        resResults(i).value = value;
                    catch ME
                        resResults(i).message = '节点存在但无法读取值';
                    end
                else
                    resResults(i).message = '节点不存在';
                end
            catch ME
                resResults(i).message = ME.message;
            end
        end

        % 统计
        varValid = sum([varResults.valid]);
        varTotal = length(varResults);
        resValid = sum([resResults.valid]);
        resTotal = length(resResults);
        totalInvalid = (varTotal - varValid) + (resTotal - resValid);

        fprintf('发现 %d 个无效节点（共 %d 个）:\n\n', totalInvalid, varTotal + resTotal);
        fprintf('变量节点: %d/%d 有效\n', varValid, varTotal);
        fprintf('结果节点: %d/%d 有效\n\n', resValid, resTotal);

        % 显示所有有效节点（简洁）
        if varValid > 0
            fprintf('变量映射有效节点 (%d 个):\n', varValid);
            for i = 1:length(varResults)
                if varResults(i).valid
                    fprintf('  ✓ %s: %.4f\n', varResults(i).name, varResults(i).value);
                end
            end
            fprintf('\n');
        end

        if resValid > 0
            fprintf('结果映射有效节点 (%d 个):\n', resValid);
            for i = 1:length(resResults)
                if resResults(i).valid
                    fprintf('  ✓ %s: %.4f\n', resResults(i).name, resResults(i).value);
                end
            end
            fprintf('\n');
        end

        % 显示所有无效节点（详细）
        if varValid < varTotal
            fprintf('变量映射无效节点 (%d 个):\n', varTotal - varValid);
            idx = 1;
            for i = 1:length(varResults)
                if ~varResults(i).valid
                    fprintf('[%d] %s: %s\n', idx, varResults(i).name, varResults(i).message);
                    fprintf('    路径: %s\n', varResults(i).path);
                    idx = idx + 1;
                end
            end
            fprintf('\n');
        end

        if resValid < resTotal
            fprintf('结果映射无效节点 (%d 个):\n', resTotal - resValid);
            idx = 1;
            for i = 1:length(resResults)
                if ~resResults(i).valid
                    fprintf('[%d] %s: %s\n', idx, resResults(i).name, resResults(i).message);
                    fprintf('    路径: %s\n', resResults(i).path);
                    idx = idx + 1;
                end
            end
            fprintf('\n');
        end

        % 如果全部有效，显示成功消息
        if totalInvalid == 0
            fprintf('========================================\n');
            fprintf('✓ 所有节点路径都有效！\n');
            fprintf('========================================\n\n');
        end

    else
        fprintf('配置文件不存在: %s\n', configPath);
    end

    fprintf('\n');

    %% 4. 建议
    fprintf('========================================\n');
    fprintf('4. 建议\n');
    fprintf('========================================\n');
    fprintf('1. 检查上面列出的流股和设备名称是否与配置文件中的匹配\n');
    fprintf('2. 在Aspen Plus中打开Variable Explorer查看完整的节点路径\n');
    fprintf('3. 根据实际的流股和设备名称更新brayton_config.json\n');
    fprintf('\n');

catch ME
    fprintf('诊断过程出错: %s\n', ME.message);
    fprintf('堆栈信息:\n');
    disp(ME.stack);
end

% 断开连接
try
    aspenApp.Close();
    delete(aspenApp);
catch
end

fprintf('已断开连接\n');
fprintf('========================================\n');
