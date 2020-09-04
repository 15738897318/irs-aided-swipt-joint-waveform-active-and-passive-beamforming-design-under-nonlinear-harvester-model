clear; clc; config_reflector;

%% * Load batch data
reSet = cell(nBatches, length(Variable.nReflectors));
for iBatch = 1 : nBatches
    load(sprintf('../data/re_reflector_%d.mat', iBatch), 'reInstance');
    reSet(iBatch, :) = reInstance;
end

%% * Average over batches
reReflector = cell(1, length(Variable.nReflectors));
for iReflector = 1 : length(Variable.nReflectors)
    reReflector{iReflector} = mean(cat(3, reSet{:, iReflector}), 3);
end
save('../data/re_reflector.mat');

%% * R-E plots
figure('name', 'R-E region vs number of reflectors');
legendString = cell(1, length(Variable.nReflectors));
for iReflector = 1 : length(Variable.nReflectors)
    plot(reReflector{iReflector}(1, :) / nSubbands, 1e6 * reReflector{iReflector}(2, :));
    legendString{iReflector} = sprintf('L = %d', Variable.nReflectors(iReflector));
    hold on;
end
hold off;
grid minor;
legend(legendString);
xlabel('Per-subband rate [bps/Hz]');
ylabel('Average output DC current [\muA]');
ylim([0 inf]);
savefig('../figures/re_reflector.fig');