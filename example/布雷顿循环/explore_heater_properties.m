% explore_heater_properties.m - 探索加热器块的所有输出属性
% 用于找到正确的热量属性名称

clear;
clc;

fprintf('========================================\n');
fprintf('加热器属性探索工具\n');
fprintf('========================================\n\n');

% 配置
modelPath = fullfile(pwd, '中间冷却再热布雷顿循环.bkp');

if ~exist(modelPath, 'file')
    error('模型文件不存在: %s', modelPath);
end

fprintf('正在连接 Aspen Plus...\n');
try
    aspenApp = actxserver('Apwn.Document');
    aspenApp.invoke('InitFromArchive2', modelPath);
    aspenApp.Visible = 0;
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
    %% 探索HEATER块的所有输出属性
    heaterNames = {'HEATER', 'HEATER2'};

    for h = 1:length(heaterNames)
        heaterName = heaterNames{h};
        fprintf('========================================\n');
        fprintf('探索 %s 块的输出属性\n', heaterName);
        fprintf('========================================\n\n');

        % 获取Output节点
        outputPath = sprintf('\\Data\\Blocks\\%s\\Output', heaterName);

        try
            outputNode = aspenApp.Tree.FindNode(outputPath);

            if ~isempty(outputNode) && ~strcmp(class(outputNode), 'handle')
                % 获取所有子元素
                elemCount = outputNode.Elements.Count;
                fprintf('找到 %d 个输出属性:\n\n', elemCount);

                % 存储热量相关的属性
                heatRelated = {};

                for i = 1:elemCount
                    try
                        elem = outputNode.Elements.Item(i-1);
                        propName = elem.Name;

                        % 构建完整路径
                        fullPath = sprintf('\\Data\\Blocks\\%s\\Output\\%s', heaterName, propName);

                        try
                            propNode = aspenApp.Tree.FindNode(fullPath);
                            if ~isempty(propNode) && ~strcmp(class(propNode), 'handle')
                                value = propNode.Value;

                                % 检查是否是热量相关属性（名称包含Q, HEAT, DUTY等）
                                propNameUpper = upper(propName);
                                isHeatRelated = contains(propNameUpper, 'Q') || ...
                                               contains(propNameUpper, 'HEAT') || ...
                                               contains(propNameUpper, 'DUTY') || ...
                                               contains(propNameUpper, 'ENERGY');

                                if isHeatRelated
                                    fprintf('  ★ [%d] %s = %.6e\n', i, propName, value);
                                    heatRelated{end+1} = propName;
                                else
                                    fprintf('  [%d] %s = %.6e\n', i, propName, value);
                                end
                            end
                        catch
                            fprintf('  [%d] %s (无法读取值)\n', i, propName);
                        end
                    catch ME
                        fprintf('  [%d] 读取失败: %s\n', i, ME.message);
                    end
                end

                fprintf('\n');

                % 总结热量相关属性
                if ~isempty(heatRelated)
                    fprintf('热量相关属性 (★标记):\n');
                    for i = 1:length(heatRelated)
                        fprintf('  %s\n', heatRelated{i});
                    end
                    fprintf('\n');
                end

            else
                fprintf('无法访问Output节点\n\n');
            end

        catch ME
            fprintf('探索失败: %s\n\n', ME.message);
        end
    end

    %% 建议
    fprintf('========================================\n');
    fprintf('建议\n');
    fprintf('========================================\n');
    fprintf('1. 查看上面标记为 ★ 的热量相关属性\n');
    fprintf('2. 选择一个合适的属性（通常是最大的数值）\n');
    fprintf('3. 将该属性名称更新到 brayton_config.json 中\n');
    fprintf('\n');

catch ME
    fprintf('探索过程出错: %s\n', ME.message);
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
