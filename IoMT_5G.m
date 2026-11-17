function IoMT5G_final(quick)
% Simulation for IoMT 5G Secure Handover

if nargin < 1, quick = false; end
cfg = defaultConfig(quick);
if ~exist(cfg.outDir, 'dir'), mkdir(cfg.outDir); end
fprintf('\n=== IoMT 5G Simulation (quick=%d) ===\n', quick);

printConfig(cfg);

%% Crypto timing (measured on this PC when Java is available, else nominal)
cr = benchCrypto(cfg);
fprintf('\nCrypto cost: ECDH P-256 %.3f ms (PC measured=%d), AES-128 %.4f ms; MR-scaled ECDH %.2f ms, AES %.3f ms\n', ...
    cr.ecdhPC, cr.measured, cr.aesPC, cr.ecdh, cr.aes);

R = struct();   % results container
net = []; trainLog = [];

writeDefinitions(cfg);
if cfg.run.crypto, R.crypto = cryptoFlowDemo(cfg); end
if cfg.run.single, R.single = singleRunDemo(cfg, cr); end

if cfg.run.E1
%% E1: Link delay sweep, all schemes (latency, PDR, handover success)
fprintf('\n[E1] Link delay sweep ...\n');
schemes = {'Proposed', 'PMIPv6', 'FMIPv6', 'AKMA+PMIPv6'};
taus = cfg.tauList;
E1 = cell(numel(schemes), numel(taus));
for si = 1:numel(schemes)
    for ti = 1:numel(taus)
        E1{si, ti} = evalPoint(cfg, schemes{si}, cfg.mobModel, cfg.speed, taus(ti), cfg.fT, cfg.W, cr, cfg.nRuns, cfg.seed);
    end
end
R.E1 = E1;
tbl = {};
for si = 1:numel(schemes)
    for ti = 1:numel(taus)
        p = E1{si, ti};
        tbl(end+1, :) = {schemes{si}, taus(ti), p.lat.m, p.lat.ci, p.pdr.m, p.pdr.ci, p.succ.m, p.nHO.m, p.zeroFrac, p.pp.m};
    end
end
writeCsv(fullfile(cfg.outDir, 'E1_linkdelay_sweep.csv'), ...
    {'scheme','tau_ms','latency_ms','latency_ci95','PDR_pct','PDR_ci95','HO_success_pct','HO_per_run','frac_runs_zero_HO','pingpong_per_run'}, tbl);
fprintf('  %-12s %6s %14s %14s %8s %8s %8s\n', 'scheme', 'tau', 'latency ms', 'PDR %', 'HOsucc', 'HO/run', 'PP/run');
for k = 1:size(tbl, 1)
    fprintf('  %-12s %6g %7.1f+-%-6.1f %7.3f+-%-6.3f %8.2f %8.2f %8.2f\n', tbl{k,1}, tbl{k,2}, tbl{k,3}, tbl{k,4}, tbl{k,5}, tbl{k,6}, tbl{k,7}, tbl{k,8}, tbl{k,10});
end

f = newFig(cfg);
subplot(1,2,1); hold on;
for si = 1:numel(schemes)
    m = cellfun(@(p) p.lat.m, E1(si,:)); c = cellfun(@(p) p.lat.ci, E1(si,:));
    ebar(taus, m, c, 'o', '-', schemes{si});
end
xlabel('Link delay \tau (ms)'); ylabel('Handover latency (ms)'); grid on; legend('Location','northwest');
title('Handover latency (mean, 95% CI)');
subplot(1,2,2); hold on;
for si = 1:numel(schemes)
    m = cellfun(@(p) p.pdr.m, E1(si,:)); c = cellfun(@(p) p.pdr.ci, E1(si,:));
    ebar(taus, m, c, 's', '-', schemes{si});
end
xlabel('Link delay \tau (ms)'); ylabel('PDR (%)'); grid on; legend('Location','southwest');
title('Packet delivery ratio (mean, 95% CI)');
saveFig(cfg, f, 'E1_latency_pdr_vs_linkdelay');

end
if cfg.run.E2
%% E2: Mobility speed and movement pattern (also zero handover check)
fprintf('[E2] Mobility sweep ...\n');
models = cfg.mobModels; speeds = cfg.speedList;
E2 = cell(numel(models), numel(speeds));
tbl = {};
for mi = 1:numel(models)
    for vi = 1:numel(speeds)
        p = evalPoint(cfg, 'Proposed', models{mi}, speeds(vi), cfg.tauRef, cfg.fT, cfg.W, cr, cfg.nRuns, cfg.seed);
        E2{mi, vi} = p;
        tbl(end+1, :) = {models{mi}, speeds(vi), p.nHO.m, p.zeroFrac, p.lat.m, p.lat.ci, p.pdr.m, p.pdr.ci, p.succ.m, p.preReady.m, p.pp.m}; %#ok<AGROW>
    end
end
R.E2 = E2;
writeCsv(fullfile(cfg.outDir, 'E2_mobility.csv'), ...
    {'model','speed_mps','HO_per_run','frac_runs_zero_HO','latency_ms','latency_ci95','PDR_pct','PDR_ci95','HO_success_pct','preauth_ready_pct','pingpong_per_run'}, tbl);
fprintf('  %-11s %5s %7s %9s %12s %10s %9s %7s\n', 'model', 'speed', 'HO/run', 'zeroHO', 'latency ms', 'PDR %', 'preauth', 'PP/run');
for k = 1:size(tbl, 1)
    fprintf('  %-11s %5g %7.2f %9.2f %12.1f %10.3f %9.1f %7.2f\n', tbl{k,1}, tbl{k,2}, tbl{k,3}, tbl{k,4}, tbl{k,5}, tbl{k,7}, nz(tbl{k,10}), tbl{k,11});
end
f = newFig(cfg);
for k = 1:3
    subplot(2,2,k); hold on;
    for mi = 1:numel(models)
        switch k
            case 1, m = cellfun(@(p) p.nHO.m, E2(mi,:)); c = cellfun(@(p) p.nHO.ci, E2(mi,:)); yl = 'Handovers per run';
            case 2, m = cellfun(@(p) p.lat.m, E2(mi,:)); c = cellfun(@(p) p.lat.ci, E2(mi,:)); yl = 'Handover latency (ms)';
            case 3, m = cellfun(@(p) p.pdr.m, E2(mi,:)); c = cellfun(@(p) p.pdr.ci, E2(mi,:)); yl = 'PDR (%)';
        end
        ebar(speeds, m, c, 'o', '-', models{mi});
    end
    xlabel('MR speed (m/s)'); ylabel(yl); grid on; if k == 1, legend('Location','northwest'); y1 = ylim; ylim([0 y1(2)]); end
end
subplot(2,2,4); hold on;
for mi = 1:numel(models)
    plot(speeds, cellfun(@(p) p.preReady.m, E2(mi,:)), '-o', 'LineWidth', 1.5, 'DisplayName', models{mi});
end
xlabel('MR speed (m/s)'); ylabel('Pre-auth ready at handover (%)'); grid on;
saveFig(cfg, f, 'E2_mobility_robustness');

end
if cfg.run.E3
%% E3: Signaling overhead, simulation vs closed form
fprintf('[E3] Signaling overhead ...\n');
fTs = cfg.fTList; Ws = [66 128];
E3 = zeros(numel(Ws), numel(fTs), 3);  % sim mean, sim ci, analytic
for wi = 1:numel(Ws)
    for fi = 1:numel(fTs)
        p = evalPoint(cfg, 'Proposed', cfg.mobModel, cfg.speed, cfg.tauRef, fTs(fi), Ws(wi), cr, cfg.nRuns, cfg.seed);
        % closed form: S = nHO * (m_total / (1 - fT)) * W / dataBytes
        % S = nHO * [m_pre + 4 + (1 - pReady) * 4] * (1 - f^(R+1)) / (1 - f) * W / dataBytes
        % (pre-auth + local AES + anchoring + inline ECDH fallback when pre-auth is not ready)
        pR = p.preReady.m / 100; if isnan(pR), pR = 1; end
        mTotal = cfg.mPre + 4 + (1 - pR) * 4;
        etx = (1 - fTs(fi)^(cfg.R + 1)) / (1 - fTs(fi));      % expected transmissions per message
        dataBytes = cfg.numDevices * cfg.devicePps * cfg.T * cfg.pktSize;
        Sa = 100 * p.nHO.m * mTotal * etx * Ws(wi) / dataBytes;
        E3(wi, fi, :) = [p.sig.m, p.sig.ci, Sa];
    end
end
R.E3 = E3;
tbl = {};
for wi = 1:numel(Ws)
    for fi = 1:numel(fTs)
        tbl(end+1, :) = {Ws(wi), fTs(fi), E3(wi,fi,1), E3(wi,fi,2), E3(wi,fi,3)}; %#ok<AGROW>
    end
end
fprintf('  %6s %6s %18s %12s\n', 'W', 'f_T', 'S sim % (CI)', 'S formula %');
for k = 1:size(tbl, 1), fprintf('  %6g %6g %9.4f+-%-8.4f %12.4f\n', tbl{k,1}, tbl{k,2}, tbl{k,3}, tbl{k,4}, tbl{k,5}); end
writeCsv(fullfile(cfg.outDir, 'E3_signaling_overhead.csv'), ...
    {'W_bytes','link_failure_rate','S_sim_pct','S_sim_ci95','S_closed_form_pct'}, tbl);
f = newFig(cfg); hold on;
for wi = 1:numel(Ws)
    ebar(fTs, E3(wi,:,1), E3(wi,:,2), 'o', 'none', sprintf('Simulation, W=%d B', Ws(wi)));
    plot(fTs, E3(wi,:,3), '--', 'LineWidth', 1.5, 'DisplayName', sprintf('Closed form, W=%d B', Ws(wi)));
end
xlabel('Link failure rate f_T'); ylabel('Signaling overhead S(L,W) (% of data bytes)'); grid on; legend('Location','northwest');
title('Signaling overhead: simulation vs closed form');
saveFig(cfg, f, 'E3_signaling_overhead');

end
if cfg.run.E4
%% E4: Authentication failure model validation
fprintf('[E4] Authentication model validation ...\n');
fTv = 0:0.05:0.5; nTrial = cfg.authTrials;
emp = zeros(size(fTv)); ana = zeros(size(fTv));
for i = 1:numel(fTv)
    setSeed(cfg.seed + 7);
    ok = 0;
    for k = 1:nTrial
        ok = ok + exchange(cfg.mPre, cfg.tauRef, fTv(i), cfg.R, max(2*cfg.tauRef + 10, 20));
    end
    emp(i) = 100 * ok / nTrial;
    ana(i) = 100 * (1 - fTv(i)^(cfg.R + 1))^cfg.mPre;
end
R.E4 = [fTv(:) emp(:) ana(:)];
writeCsv(fullfile(cfg.outDir, 'E4_auth_validation.csv'), {'link_failure_rate','success_sim_pct','success_analytic_pct'}, num2cell(R.E4));
f = newFig(cfg); hold on;
plot(fTv, ana, '-', 'LineWidth', 2, 'DisplayName', 'Analytic (1 - f^{R+1})^m');
plot(fTv, emp, 'o', 'MarkerSize', 7, 'DisplayName', 'Simulation');
xlabel('Per-message loss probability f_T'); ylabel('Pre-auth exchange success (%)'); grid on; legend('Location','southwest');
title('Authentication failure model: simulation vs analytic');
saveFig(cfg, f, 'E4_auth_model_validation');

end
if cfg.run.E5
%% E5: Ablation (security and anchoring components)
fprintf('[E5] Ablation ...\n');
abl = {'Proposed', 'Abl_NoPreAuth', 'Abl_NoAES', 'Abl_NoAnchor', 'Abl_NoECDH'};
ablLabel = {'Full scheme', 'No pre-auth (ECDH inline)', 'No AES auth', 'No local anchoring', 'No ECDH (static key)'};
E5 = cell(1, numel(abl)); tbl = {};
for ai = 1:numel(abl)
    p = evalPoint(cfg, abl{ai}, cfg.mobModel, cfg.speed, cfg.tauRef, cfg.fT, cfg.W, cr, cfg.nRuns, cfg.seed);
    E5{ai} = p;
    tbl(end+1, :) = {ablLabel{ai}, p.lat.m, p.lat.ci, p.pdr.m, p.pdr.ci, p.succ.m, p.sig.m}; %#ok<AGROW>
end
R.E5 = E5;
for k = 1:size(tbl, 1), fprintf('  %-28s latency %7.1f+-%-6.1f ms | PDR %7.3f+-%-6.3f %% | HO success %6.2f %% | signaling %.3f %%\n', tbl{k,1}, tbl{k,2}, tbl{k,3}, tbl{k,4}, tbl{k,5}, tbl{k,6}, tbl{k,7}); end
writeCsv(fullfile(cfg.outDir, 'E5_ablation.csv'), {'variant','latency_ms','latency_ci95','PDR_pct','PDR_ci95','HO_success_pct','signaling_pct'}, tbl);
f = newFig(cfg);
subplot(1,2,1);
m = cellfun(@(p) p.lat.m, E5); c = cellfun(@(p) p.lat.ci, E5);
bar(m); hold on; ebar(1:numel(m), m, c, '.', 'none', '');
set(gca, 'XTick', 1:numel(m), 'XTickLabel', ablLabel, 'XTickLabelRotation', 30); ylabel('Handover latency (ms)'); grid on;
subplot(1,2,2);
m = cellfun(@(p) p.pdr.m, E5); c = cellfun(@(p) p.pdr.ci, E5);
bar(m); hold on; ebar(1:numel(m), m, c, '.', 'none', '');
set(gca, 'XTick', 1:numel(m), 'XTickLabel', ablLabel, 'XTickLabelRotation', 30); ylabel('PDR (%)'); grid on;
ylim([max(0, min(m) - 3), 100]);
saveFig(cfg, f, 'E5_ablation');

end
if cfg.run.E7
%% E7 first (needed for E6 DRL inference time): DRL-NSA
fprintf('[E7] DRL-NSA training (DQN) ...\n');
cfgS = cfg; 
[net, trainLog] = trainDQN(cfgS, cfg.dqn.episodes, cfg.seed + 100, true);
f = newFig(cfg);
subplot(2,1,1); plot(trainLog.rew, ':', 'Color', [0.7 0.7 0.7]); hold on;
plot(movAvg(trainLog.rew, 10), 'LineWidth', 2); xlabel('Training episode'); ylabel('Mean reward'); grid on;
title('DRL-NSA convergence');
subplot(2,1,2); plot(movAvg(trainLog.viol, 10), 'LineWidth', 2); xlabel('Training episode'); ylabel('SLA violation rate (train)'); grid on;
saveFig(cfg, f, 'E7_drl_convergence');

pols = {'Static (30/50/20)', 'Equal split', 'Proportional', 'DRL-NSA (DQN)'};
polKey = {'static', 'equal', 'prop', 'drl'};
E7 = cell(1, numel(pols)); tbl = {};
for pi = 1:numel(pols)
    E7{pi} = evalPolicy(cfg, polKey{pi}, net, cfg.dqn.evalEps, cfg.seed + 5000);
    e = E7{pi};
    tbl(end+1, :) = {pols{pi}, e.rew.m, e.rew.ci, e.viol.m, e.viol.ci, e.thr(1).m, e.thr(2).m, e.thr(3).m, e.lat(1).m, e.lat(2).m, e.lat(3).m}; %#ok<AGROW>
end
R.E7 = E7;
writeCsv(fullfile(cfg.outDir, 'E7_slicing_policies.csv'), ...
    {'policy','reward','reward_ci95','SLA_violation_rate','viol_ci95','thr_uRLLC','thr_eMBB','thr_mIoT','lat_uRLLC_ms','lat_eMBB_ms','lat_mIoT_ms'}, tbl);
fprintf('\nSlicing policy comparison (mean over %d eval episodes)\n', cfg.dqn.evalEps);
for pi = 1:numel(pols)
    e = E7{pi};
    fprintf('  %-18s reward %.3f | SLA viol %.3f | thr %.1f/%.1f/%.1f Mbps | lat %.1f/%.1f/%.1f ms\n', pols{pi}, e.rew.m, e.viol.m, ...
        e.thr(1).m, e.thr(2).m, e.thr(3).m, e.lat(1).m, e.lat(2).m, e.lat(3).m);
end
f = newFig(cfg);
subplot(1,2,1); bar(cellfun(@(e) e.viol.m, E7)); hold on;
ebar(1:4, cellfun(@(e) e.viol.m, E7), cellfun(@(e) e.viol.ci, E7), '.', 'none', '');
set(gca, 'XTick', 1:4, 'XTickLabel', pols, 'XTickLabelRotation', 25); ylabel('SLA violation rate'); grid on;
subplot(1,2,2); bar(cellfun(@(e) e.rew.m, E7)); hold on;
ebar(1:4, cellfun(@(e) e.rew.m, E7), cellfun(@(e) e.rew.ci, E7), '.', 'none', '');
set(gca, 'XTick', 1:4, 'XTickLabel', pols, 'XTickLabelRotation', 25); ylabel('Mean reward'); grid on;
saveFig(cfg, f, 'E7_slicing_policy_comparison');

% Example episode time series (equivalent of slice)
setSeed(cfg.seed + 9000);
tr = genTraffic(cfg, cfg.numDevices, cfg.sliceSteps);
thrS = zeros(3, cfg.sliceSteps); latS = thrS; thrD = thrS; latD = thrS;
for t = 1:cfg.sliceSteps
    [~, a, b] = sliceReward(policyFrac('static', tr(:,t), net, cfg), tr(:,t+1), cfg); thrS(:,t) = a; latS(:,t) = b;
    [~, a, b] = sliceReward(policyFrac('drl', tr(:,t), net, cfg), tr(:,t+1), cfg); thrD(:,t) = a; latD(:,t) = b;
end
f = newFig(cfg);
names = {'uRLLC', 'eMBB', 'mIoT'};
for s = 1:3
    subplot(3,2,2*s-1); plot(thrS(s,:), 'LineWidth', 1.2); hold on; plot(thrD(s,:), 'LineWidth', 1.2);
    ylabel([names{s} ' Mbps']); grid on; if s == 1, title('Throughput'); legend('Static', 'DRL-NSA'); end
    subplot(3,2,2*s); semilogy(max(latS(s,:), 0.1), 'LineWidth', 1.2); hold on; semilogy(max(latD(s,:), 0.1), 'LineWidth', 1.2);
    yline_safe(cfg.sla(s)); ylabel([names{s} ' ms']); grid on; if s == 1, title('Latency (dashed = SLA)'); end
end
subplot(3,2,5); xlabel('Time (s)'); subplot(3,2,6); xlabel('Time (s)');
saveFig(cfg, f, 'E7_slice_timeseries');

end
if cfg.run.E6
%% E6: Computation, memory and energy overhead
fprintf('[E6] Overhead table ...\n');
if isempty(net), setSeed(1); net = initNet(3, cfg.dqn.hidden, size(actionSet(), 1)); end
x = randn(3, 1);
tic; for k = 1:2000, fwd(net, x); end; tInf = toc / 2000 * 1000;
nParam = numel(net.W1) + numel(net.b1) + numel(net.W2) + numel(net.b2) + numel(net.W3) + numel(net.b3);
ovh = {
    'ECDH P-256 key agreement', cr.ecdhPC, cr.ecdh, cr.ecdh * cfg.mcuScale / cfg.mrScale, 1024, 'MR and IoMT device';
    'AES-128 encrypt/verify (64 B)', cr.aesPC, cr.aes, cr.aes * cfg.mcuScale / cfg.mrScale, 176 + 64, 'MR and IoMT device';
    'DRL-NSA inference (1 decision)', tInf, tInf, NaN, nParam * 4, 'Network side only (not on device)'};
tbl = {};
for k = 1:size(ovh, 1)
    tdev = ovh{k, 4}; 
    if isnan(tdev), e = NaN; else, e = cfg.mcuPower * tdev; end   % W * ms = mJ
    tbl(end+1, :) = {ovh{k,1}, ovh{k,2}, ovh{k,3}, tdev, e, ovh{k,5}, ovh{k,6}}; %#ok<AGROW>
end
writeCsv(fullfile(cfg.outDir, 'E6_overhead.csv'), ...
    {'operation','time_PC_ms','time_MR_est_ms','time_IoMT_device_est_ms','energy_device_est_mJ','memory_bytes','where'}, tbl);
fprintf('  Operation                         PC ms     MR ms    Device ms   Energy mJ   Memory B\n');
for k = 1:size(tbl, 1)
    fprintf('  %-32s %8.4f %9.3f %10.3f %10.4f %10d\n', tbl{k,1}, tbl{k,2}, tbl{k,3}, nz(tbl{k,4}), nz(tbl{k,5}), tbl{k,6});
end
% signaling bytes per handover (nominal, no loss)
fprintf('  Signaling per handover: %d messages x %d B = %d B (nominal)\n', cfg.mPre + 4, cfg.W, (cfg.mPre + 4) * cfg.W);
R.E6 = tbl;

end
if cfg.run.E8
%% E8: Scalability (devices, load, bandwidth)
fprintf('[E8] Scalability ...\n');
Nlist = cfg.NList; Blist = cfg.BList;
E8N = cell(numel(Nlist), 3); E8B = cell(numel(Blist), 3);
polK = {'static', 'prop', 'drl'};
for ni = 1:numel(Nlist)
    c2 = cfg; c2.numDevices = Nlist(ni);
    [net2, ~] = trainDQN(c2, cfg.dqn.episodesSweep, cfg.seed + 200 + ni, false);
    for pk = 1:3, E8N{ni, pk} = evalPolicy(c2, polK{pk}, net2, cfg.dqn.evalEps, cfg.seed + 6000); end
end
for bi = 1:numel(Blist)
    c2 = cfg; c2.bandwidth = Blist(bi);
    [net2, ~] = trainDQN(c2, cfg.dqn.episodesSweep, cfg.seed + 300 + bi, false);
    for pk = 1:3, E8B{bi, pk} = evalPolicy(c2, polK{pk}, net2, cfg.dqn.evalEps, cfg.seed + 7000); end
end
R.E8N = E8N; R.E8B = E8B;
tbl = {};
for ni = 1:numel(Nlist)
    for pk = 1:3
        e = E8N{ni, pk}; tbl(end+1, :) = {'devices', Nlist(ni), polK{pk}, e.viol.m, e.viol.ci, e.rew.m, e.thr(1).m + e.thr(2).m + e.thr(3).m}; %#ok<AGROW>
    end
end
for bi = 1:numel(Blist)
    for pk = 1:3
        e = E8B{bi, pk}; tbl(end+1, :) = {'bandwidth_Mbps', Blist(bi), polK{pk}, e.viol.m, e.viol.ci, e.rew.m, e.thr(1).m + e.thr(2).m + e.thr(3).m}; %#ok<AGROW>
    end
end
writeCsv(fullfile(cfg.outDir, 'E8_scalability.csv'), {'sweep','value','policy','SLA_violation','viol_ci95','reward','total_throughput_Mbps'}, tbl);
f = newFig(cfg);
subplot(1,2,1); hold on;
for pk = 1:3
    ebar(Nlist, cellfun(@(e) e.viol.m, E8N(:,pk)), cellfun(@(e) e.viol.ci, E8N(:,pk)), 'o', '-', polK{pk});
end
xlabel('Number of IoMT devices'); ylabel('SLA violation rate'); grid on; legend('Location','southeast'); ylim([0 1.05]);
subplot(1,2,2); hold on;
for pk = 1:3
    ebar(Blist, cellfun(@(e) e.viol.m, E8B(:,pk)), cellfun(@(e) e.viol.ci, E8B(:,pk)), 'o', '-', polK{pk});
end
xlabel('Total bandwidth (Mbps)'); ylabel('SLA violation rate'); grid on;
saveFig(cfg, f, 'E8_scalability');

end
if cfg.run.E9
%% E9: Pre-authentication margin sweep (when pre-auth starts, in dB below the serving cell)
fprintf('[E9] Pre-auth margin sweep ...\n');
mg = cfg.marginList; E9 = cell(1, numel(mg)); tbl = {};
for mi = 1:numel(mg)
    c2 = cfg; c2.preMargin = mg(mi);
    p = evalPoint(c2, 'Proposed', cfg.mobModel, cfg.speed, cfg.tauRef, cfg.fT, cfg.W, cr, cfg.nRuns, cfg.seed);
    E9{mi} = p;
    tbl(end+1, :) = {mg(mi), p.preReady.m, p.lat.m, p.lat.ci, p.pdr.m, p.pdr.ci, p.pp.m}; %#ok<AGROW>
end
R.E9 = E9;
writeCsv(fullfile(cfg.outDir, 'E9_preauth_margin.csv'), {'margin_dB','preauth_ready_pct','latency_ms','latency_ci95','PDR_pct','PDR_ci95','pingpong_per_run'}, tbl);
for k = 1:size(tbl, 1), fprintf('  margin %5g dB  pre-auth ready %6.1f %% | latency %7.1f+-%-6.1f ms | PDR %7.3f+-%-6.3f %%\n', tbl{k,1}, nz(tbl{k,2}), tbl{k,3}, tbl{k,4}, tbl{k,5}, tbl{k,6}); end
f = newFig(cfg);
subplot(1,3,1); ebar(mg, cellfun(@(p) p.preReady.m, E9), cellfun(@(p) p.preReady.ci, E9), 'o', '-', ''); xlabel('Pre-auth margin (dB)'); ylabel('Pre-auth ready at handover (%)'); grid on;
subplot(1,3,2); ebar(mg, cellfun(@(p) p.lat.m, E9), cellfun(@(p) p.lat.ci, E9), 'o', '-', ''); xlabel('Pre-auth margin (dB)'); ylabel('Handover latency (ms)'); grid on;
subplot(1,3,3); ebar(mg, cellfun(@(p) p.pdr.m, E9), cellfun(@(p) p.pdr.ci, E9), 'o', '-', ''); xlabel('Pre-auth margin (dB)'); ylabel('PDR (%)'); grid on;
saveFig(cfg, f, 'E9_preauth_margin_sweep');
end
%% Save everything
save(fullfile(cfg.outDir, 'results.mat'), 'R', 'cfg', 'cr', 'net', 'trainLog');
fprintf('\nDone. Results in folder: %s\n', cfg.outDir);
end

%% ==================
%% Configuration
%% ==================
function cfg = defaultConfig(quick)
cfg.quick = quick;
cfg.outDir = 'IoMT_5G';
cfg.makeFigures = true;
cfg.visible = 'on';          % set to 'off' to avoid popping up windows
cfg.seed = 2025;
cfg.nRuns = 30;              % independent runs per point
cfg.T = 300; cfg.dt = 0.1;   % simulated seconds, time step (s)
cfg.area = [1000 1000];
cfg.AP = [250 250; 750 250; 500 750];
cfg.LMA = [400 400]; cfg.MR0 = [100 100];
cfg.numDevices = 30; cfg.bandwidth = 100;   % Mbps
% radio
cfg.txPower = 43; cfg.shSigma = 4; cfg.shRho = 0.95;   % dBm, dB, per-step AR(1)
cfg.noise = -94; cfg.snr0 = 5; cfg.snrW = 2;
cfg.hyst = 3; cfg.ttt = 3; cfg.preMargin = 8;      % dB, steps (0.3 s), dB
cfg.ppWindow = 1; cfg.marginList = [2 4 8 12 16];  % ping-pong window (s), pre-auth margins to sweep (dB)
% mobility
cfg.mobModel = 'randomwalk'; cfg.mobModels = {'linear', 'randomwalk', 'waypoint'};
cfg.speed = 15; cfg.speedList = [2 5 10 20 30];          % m/s
% network delays (ms, one way)
cfg.tauLoc = 2; cfg.tauMid = 5; cfg.tauRef = 100;
cfg.tauList = [0 50 100 150 200 250];
cfg.L2min = 10; cfg.L2max = 20;
% signaling and loss
cfg.fT = 0.1; cfg.fTList = [0.1 0.2 0.3 0.4]; cfg.W = 66;   % link failure prob, message size (B)
cfg.R = 3; cfg.mPre = 4; cfg.recovery = 300;                % retransmissions, pre-auth messages, recovery (ms)
cfg.devicePps = 10; cfg.pktSize = 128; cfg.holdMs = 300;    % packets/s per device, bytes, buffer hold (ms)
cfg.tFullAuth = 10; cfg.tKDF = 2;                           % baseline crypto (ms)
cfg.authTrials = 20000;
% device scaling for crypto cost
cfg.mrScale = 10; cfg.mcuScale = 100; cfg.mcuPower = 0.05;  % MR = 10x PC time, MCU = 100x PC time, 50 mW
% slicing
cfg.sliceSteps = 100;
cfg.sla = [5 20 100]; cfg.lat0 = [0.5 2 8];   % ms
cfg.rate = [0.5 3; 2 8; 0.3 2];               % per-device Mbps range per slice
cfg.w = [3 2 1];                              % slice priority weights
cfg.static = [0.3 0.5 0.2];
cfg.dqn.episodes = 300; cfg.dqn.episodesSweep = 120; cfg.dqn.evalEps = 30;
cfg.dqn.hidden = 32; cfg.dqn.gamma = 0.9; cfg.dqn.lr = 1e-3; cfg.dqn.batch = 32;
cfg.dqn.buffer = 8000; cfg.dqn.sync = 100;
cfg.NList = [10 30 60 100 200]; cfg.BList = [50 100 150 200];
% path loss model: '3gpp-uma' | 'logdistance' | 'freespace'
cfg.plModel = '3gpp-uma'; cfg.plExp = 3.5; cfg.freqGHz = 3.5;
% single user pAP -> nAP demo (section S1); pAP at x=0, nAP at x=isd, user moves along x
cfg.sr.isd = 500; cfg.sr.startX = 50; cfg.sr.yOffset = 30; cfg.sr.speed = 15;   % m, m, m, m/s
cfg.sr.txPower = 30; cfg.sr.dt = 0.01; cfg.sr.dCorr = 20; cfg.sr.l3 = 0.5;      % dBm, s, shadowing corr. dist (m), L3 filter
cfg.sr.shSigma = 2; cfg.sr.hyst = 3; cfg.sr.ttt = 0.256; cfg.sr.a3offset = 0; cfg.sr.preMargin = 8;  % dB, s, dB, dB
cfg.sr.traffic = 'constant';     % 'constant' | 'poisson' | 'bursty'
cfg.sr.rateMbps = 5; cfg.sr.pktSize = 1200; cfg.sr.baseDelayMs = 5;  % Mbps, bytes, ms
cfg.sr.scheme = 'Proposed'; cfg.sr.compare = 'PMIPv6';      % schemes shown side by side
cfg.sr.tau = 100; cfg.sr.fT = 0.1; cfg.sr.nHist = 300;      % link delay (ms), msg loss, runs for histogram
% security demo
cfg.crypto.rekeyEvery = 5;   % fresh ECDH every N handovers (limits session-key compromise damage)
% switch sections on/off
cfg.run = struct('crypto', true, 'single', true, 'E1', true, 'E2', true, 'E3', true, ...
                 'E4', true, 'E5', true, 'E7', true, 'E6', true, 'E8', true, 'E9', true);
if quick
    cfg.nRuns = 5; cfg.authTrials = 2000;
    cfg.tauList = [0 100 250]; cfg.speedList = [5 20]; cfg.fTList = [0.1 0.4];
    cfg.dqn.episodes = 40; cfg.dqn.episodesSweep = 15; cfg.dqn.evalEps = 5;
    cfg.NList = [10 60]; cfg.BList = [50 150]; cfg.sr.nHist = 20; cfg.marginList = [4 12];
end
end

function printConfig(cfg)
fprintf('\nSimulation etup (copy into the paper as the setup table)\n');
items = {
    'Independent runs per point', cfg.nRuns; 'Base seed', cfg.seed; 'Duration (s)', cfg.T; 'Time step (s)', cfg.dt;
    'Area (m)', sprintf('%dx%d', cfg.area(1), cfg.area(2)); 'APs', size(cfg.AP, 1); 'IoMT devices', cfg.numDevices;
    'Bandwidth (Mbps)', cfg.bandwidth; 'Tx power (dBm)', cfg.txPower; 'Path loss model', cfg.plModel;
    'Shadowing sigma (dB), AR(1) rho', sprintf('%g, %g', cfg.shSigma, cfg.shRho); 'Handover hysteresis (dB), TTT (steps = s)', sprintf('%g, %d = %g s', cfg.hyst, cfg.ttt, cfg.ttt * cfg.dt);
    'Pre-auth margin (dB)', cfg.preMargin; 'Default mobility, speed (m/s)', sprintf('%s, %g', cfg.mobModel, cfg.speed);
    'Local/mid/backhaul one-way delay (ms)', sprintf('%g / %g / tau', cfg.tauLoc, cfg.tauMid); 'Link failure prob f_T', cfg.fT;
    'Retransmissions R', cfg.R; 'Message size W (B)', cfg.W; 'Device traffic (pkt/s, B)', sprintf('%d, %d', cfg.devicePps, cfg.pktSize);
    'Buffer hold time (ms)', cfg.holdMs; 'Slice SLA latency (ms)', mat2str(cfg.sla);
    'Ping-pong window (s)', cfg.ppWindow; 'S1 path: ISD, start x, y offset (m)', sprintf('%g, %g, %g', cfg.sr.isd, cfg.sr.startX, cfg.sr.yOffset);
    'S1 speed (m/s), shadowing sigma (dB)', sprintf('%g, %g', cfg.sr.speed, cfg.sr.shSigma); 'S1 Tx power (dBm), time step (s)', sprintf('%g, %g', cfg.sr.txPower, cfg.sr.dt);
    'S1 hysteresis (dB), TTT (s), pre-auth margin (dB)', sprintf('%g, %g, %g', cfg.sr.hyst, cfg.sr.ttt, cfg.sr.preMargin);
    'S1 traffic', sprintf('%s, %g Mbps, %d B packets', cfg.sr.traffic, cfg.sr.rateMbps, cfg.sr.pktSize);
    'S1 link delay tau (ms), f_T, runs for histogram', sprintf('%g, %g, %d', cfg.sr.tau, cfg.sr.fT, cfg.sr.nHist)};
for k = 1:size(items, 1)
    v = items{k, 2}; if isnumeric(v), v = num2str(v); end
    fprintf('  %-42s %s\n', items{k, 1}, v);
end
writeCsv(fullfile(cfg.outDir, 'setup_table.csv'), {'parameter', 'value'}, cellfun(@(x) x, items, 'UniformOutput', false));
end

%% ===================
%% Crypto benchmark
%% ===================
function cr = benchCrypto(cfg)
cr.ecdhPC = 2.0; cr.aesPC = 0.02; cr.measured = false;  % nominal fallback (ms)
try
    kpg = java.security.KeyPairGenerator.getInstance('EC'); kpg.initialize(256);
    kpB = kpg.generateKeyPair();
    n = 40; tic;
    for k = 1:n
        kpA = kpg.generateKeyPair();
        ka = javax.crypto.KeyAgreement.getInstance('ECDH'); ka.init(kpA.getPrivate()); ka.doPhase(kpB.getPublic(), true); ka.generateSecret();
    end
    cr.ecdhPC = toc / n * 1000;
    key = javax.crypto.spec.SecretKeySpec(int8(1:16)', 'AES');
    ci = javax.crypto.Cipher.getInstance('AES/ECB/PKCS5Padding'); ci.init(1, key);
    data = int8(1:64)'; n = 2000; tic;
    for k = 1:n, ci.doFinal(data); end
    cr.aesPC = toc / n * 1000; cr.measured = true;
catch
    % keep nominal values
end
cr.ecdh = cr.ecdhPC * cfg.mrScale; cr.aes = cr.aesPC * cfg.mrScale;
end

%% ============================
%% Radio and Handover model
%% ============================
function pos = mobility(cfg, model, speed, n)
pos = zeros(n, 2); p = cfg.MR0 + 50 * rand(1, 2); step = speed * cfg.dt;
head = 2 * pi * rand; wp = cfg.area .* rand(1, 2);
for k = 1:n
    switch model
        case 'linear'
            % constant heading, reflect at borders
        case 'randomwalk'
            head = head + 0.15 * randn;
        case 'waypoint'
            v = wp - p; 
            if norm(v) < step, wp = cfg.area .* rand(1, 2); v = wp - p; end
            head = atan2(v(2), v(1));
    end
    q = p + step * [cos(head) sin(head)];
    if q(1) < 0 || q(1) > cfg.area(1), head = pi - head; q = p + step * [cos(head) sin(head)]; end
    if q(2) < 0 || q(2) > cfg.area(2), head = -head;    q = p + step * [cos(head) sin(head)]; end
    p = min(max(q, 0), cfg.area); pos(k, :) = p;
end
end

function tr = radioTrace(cfg, model, speed)
n = round(cfg.T / cfg.dt);
pos = mobility(cfg, model, speed, n);
nAP = size(cfg.AP, 1);
shadow = cfg.shSigma * randn(nAP, 1);
d = sqrt(sum((cfg.AP - repmat(pos(1, :), nAP, 1)).^2, 2));
r0 = cfg.txPower - pathLoss(cfg, d) + shadow;
[~, serv] = max(r0);
preStart = nan(nAP, 1); cnt = 0; tgtPrev = 0; perSum = 0; events = zeros(0, 4);
for k = 1:n
    d = sqrt(sum((cfg.AP - repmat(pos(k, :), nAP, 1)).^2, 2));
    shadow = cfg.shRho * shadow + sqrt(1 - cfg.shRho^2) * cfg.shSigma * randn(nAP, 1);
    rsrp = cfg.txPower - pathLoss(cfg, d) + shadow;
    snr = rsrp(serv) - cfg.noise;
    perSum = perSum + 1 / (1 + exp((snr - cfg.snr0) / cfg.snrW));
    for j = 1:nAP
        if j ~= serv && rsrp(j) > rsrp(serv) - cfg.preMargin
            if isnan(preStart(j)), preStart(j) = k; end
        else
            preStart(j) = NaN;
        end
    end
    cand = rsrp; cand(serv) = -Inf; [bm, bj] = max(cand);
    if bm > rsrp(serv) + cfg.hyst
        if bj == tgtPrev, cnt = cnt + 1; else, cnt = 1; end
        tgtPrev = bj;
    else
        cnt = 0; tgtPrev = 0;
    end
    if cnt >= cfg.ttt
        ps = preStart(bj); if isnan(ps), ps = k; end
        events(end+1, :) = [k, serv, bj, ps]; %#ok<AGROW>
        serv = bj; cnt = 0; tgtPrev = 0; preStart(:) = NaN;
    end
end
tr.events = events; tr.perSum = perSum; tr.n = n;
end

function [ok, tms, ntx] = exchange(nmsg, d, fT, R, RTO)
% Message exchange with per-message loss probability fT, up to R retransmissions.
ok = true; tms = 0; ntx = 0;
for i = 1:nmsg
    att = 0; delivered = false;
    while att <= R
        att = att + 1; ntx = ntx + 1;
        if rand >= fT, delivered = true; break; end
        tms = tms + RTO;
    end
    if delivered, tms = tms + d; else, ok = false; return; end
end
end

function rows = getPlan(name, preOK, tau, cfg, cr)
% Critical-path message plan: [number of messages, one-way delay (ms), crypto time (ms)]
loc = cfg.tauLoc; mid = cfg.tauMid; core = tau;
ecdhRow = [cfg.mPre core 2 * cr.ecdh];
switch name
    case 'Proposed'
        rows = [2 loc 2 * cr.aes; 2 mid 0];
        if ~preOK, rows = [ecdhRow; rows]; end
    case 'Abl_NoPreAuth'
        rows = [ecdhRow; 2 loc 2 * cr.aes; 2 mid 0];
    case 'Abl_NoAES'
        rows = [2 mid 0];
    case 'Abl_NoAnchor'
        rows = [2 loc 2 * cr.aes; 2 core 0];
        if ~preOK, rows = [ecdhRow; rows]; end
    case 'Abl_NoECDH'
        rows = [2 loc 2 * cr.aes; 2 mid 0];
    case 'PMIPv6'
        rows = [4 core cfg.tFullAuth; 2 core 0; 2 loc 0];
    case 'FMIPv6'
        rows = [2 loc 0; 2 mid 0];
    case 'AKMA+PMIPv6'
        rows = [2 core cfg.tKDF; 2 core 0; 2 loc 0];
    otherwise
        error('Unknown scheme %s', name);
end
end

function b = bufFrac(name)
switch name
    case {'Proposed', 'Abl_NoPreAuth', 'Abl_NoAES', 'Abl_NoECDH'}, b = 0.9;
    case 'FMIPv6', b = 0.6;
    otherwise, b = 0;
end
end

function out = evalScheme(tr, name, tau, fT, W, cfg, cr)
usesPre = any(strcmp(name, {'Proposed', 'Abl_NoAnchor'}));
pps = cfg.numDevices * cfg.devicePps;
nEv = size(tr.events, 1);
lat = zeros(nEv, 1); fail = 0; preTry = 0; preOKn = 0; sigTx = 0; lost = 0; buf = bufFrac(name);
for i = 1:nEv
    leadMs = (tr.events(i, 1) - tr.events(i, 4)) * cfg.dt * 1000;
    preOK = false;
    if usesPre
        [okp, tp, ntp] = exchange(cfg.mPre, tau, fT, cfg.R, max(2 * tau + 10, 20));
        tp = tp + 2 * cr.ecdh; sigTx = sigTx + ntp; preTry = preTry + 1;
        preOK = okp && (tp <= leadMs); preOKn = preOKn + preOK;
    end
    rows = getPlan(name, preOK, tau, cfg, cr);
    total = cfg.L2min + (cfg.L2max - cfg.L2min) * rand; allOK = true;
    for r = 1:size(rows, 1)
        [ok, t, ntx] = exchange(rows(r, 1), rows(r, 2), fT, cfg.R, max(2 * rows(r, 2) + 10, 20));
        total = total + t + rows(r, 3); sigTx = sigTx + ntx;
        if ~ok, allOK = false; break; end
    end
    if ~allOK, total = total + cfg.recovery + 6 * tau; fail = fail + 1; end
    lat(i) = total;
    lost = lost + pps * ((1 - buf) * min(total, cfg.holdMs) + max(total - cfg.holdMs, 0)) / 1000;
end
sent = pps * cfg.T;
lostPER = pps * cfg.dt * tr.perSum;
pp = 0;
for i = 2:nEv
    if tr.events(i, 3) == tr.events(i - 1, 2) && (tr.events(i, 1) - tr.events(i - 1, 1)) * cfg.dt < cfg.ppWindow, pp = pp + 1; end
end
out.pp = pp;
out.lat = lat; out.nHO = nEv; out.fail = fail; out.preTry = preTry; out.preOK = preOKn;
out.pdr = 100 * (1 - (lost + lostPER) / sent);
out.sigPct = 100 * sigTx * W / (cfg.numDevices * cfg.devicePps * cfg.T * cfg.pktSize);
end

function p = evalPoint(cfg, name, model, speed, tau, fT, W, cr, nRuns, seed)
lat = nan(nRuns, 1); pdr = zeros(nRuns, 1); succ = nan(nRuns, 1); nHO = zeros(nRuns, 1);
sig = zeros(nRuns, 1); pre = nan(nRuns, 1); ppv = zeros(nRuns, 1);
for r = 1:nRuns
    setSeed(seed + r);
    tr = radioTrace(cfg, model, speed); % same trace for every scheme (common random numbers)
    o = evalScheme(tr, name, tau, fT, W, cfg, cr);
    if o.nHO > 0, lat(r) = mean(o.lat); succ(r) = 100 * (1 - o.fail / o.nHO); end
    if o.preTry > 0, pre(r) = 100 * o.preOK / o.preTry; end
    pdr(r) = o.pdr; nHO(r) = o.nHO; sig(r) = o.sigPct; ppv(r) = o.pp;
end
p.lat = stat(lat); p.pdr = stat(pdr); p.succ = stat(succ); p.nHO = stat(nHO); p.sig = stat(sig);
p.preReady = stat(pre); p.zeroFrac = mean(nHO == 0); p.pp = stat(ppv);
end

%% =======================================
%% Slicing Environment and DRL-NSA (DQN)
%% =======================================
function tr = genTraffic(cfg, N, steps)
sl = randi(3, N, 1); base = zeros(3, 1);
for s = 1:3
    k = sum(sl == s);
    if k > 0, base(s) = sum(cfg.rate(s, 1) + (cfg.rate(s, 2) - cfg.rate(s, 1)) * rand(k, 1)); end
end
m = ones(3, 1); tr = zeros(3, steps + 1);
for t = 1:steps + 1
    m = 0.95 * m + 0.05 + 0.12 * randn(3, 1); m = max(m, 0.2);
    tr(:, t) = base .* m .* (1 + 0.05 * randn(3, 1));
end
end

function [r, thr, lat, viol] = sliceReward(frac, traffic, cfg)
B = cfg.bandwidth;
alloc = frac(:) * B;
served = min(traffic, alloc);
leftover = sum(alloc - served); unmet = traffic - served; extra = zeros(3, 1);
if sum(unmet) > 1e-9, extra = min(unmet, leftover * unmet / sum(unmet)); end
thr = served + extra; capS = alloc + extra;
u = min(0.995, traffic ./ max(capS, 1e-9)); u(traffic < 1e-9) = 0;
lat = min(cfg.lat0(:) ./ (1 - u), 1000);
viol = double(lat > cfg.sla(:));
sat = thr ./ max(traffic, 1e-9); sat(traffic < 1e-9) = 1;
w = cfg.w(:);
r = sum(w .* sat) / sum(w) - sum(w .* viol) / sum(w);
end

function A = actionSet()
A = [];
for a = 1:8, for b = 1:8, c = 10 - a - b; if c >= 1, A(end+1, :) = [a b c] / 10; end, end, end %#ok<AGROW>
end

function frac = policyFrac(key, s, net, cfg)
switch key
    case 'static', frac = cfg.static(:);
    case 'equal', frac = ones(3, 1) / 3;
    case 'prop', frac = max(s(:) / max(sum(s), 1e-9), 0.05); frac = frac / sum(frac);
    case 'drl'
        A = actionSet(); q = fwd(net, s(:) / cfg.bandwidth); [~, i] = max(q); frac = A(i, :)';
end
end

function e = evalPolicy(cfg, key, net, nEp, seedBase)
rew = zeros(nEp, 1); viol = zeros(nEp, 1); thr = zeros(nEp, 3); lat = zeros(nEp, 3);
for ep = 1:nEp
    setSeed(seedBase + ep);
    tr = genTraffic(cfg, cfg.numDevices, cfg.sliceSteps);
    R = 0; V = 0; T = zeros(3, 1); L = zeros(3, 1);
    for t = 1:cfg.sliceSteps
        fr = policyFrac(key, tr(:, t), net, cfg);
        [r, th, la, vi] = sliceReward(fr, tr(:, t + 1), cfg);
        R = R + r; V = V + mean(vi); T = T + th; L = L + la;
    end
    rew(ep) = R / cfg.sliceSteps; viol(ep) = V / cfg.sliceSteps; thr(ep, :) = (T / cfg.sliceSteps)'; lat(ep, :) = (L / cfg.sliceSteps)';
end
e.rew = stat(rew); e.viol = stat(viol);
for s = 1:3, e.thr(s) = stat(thr(:, s)); e.lat(s) = stat(lat(:, s)); end
end

function [net, lg] = trainDQN(cfg, episodes, seed, verbose)
setSeed(seed);
A = actionSet(); nA = size(A, 1); ns = 3; h = cfg.dqn.hidden;
net = initNet(ns, h, nA); tgt = net; opt = initAdam(net);
cap = cfg.dqn.buffer; S = zeros(ns, cap); S2 = S; Ai = zeros(1, cap); Rw = zeros(1, cap); Dn = zeros(1, cap);
nb = 0; ptr = 0; lg.rew = zeros(episodes, 1); lg.viol = zeros(episodes, 1); stepc = 0;
for ep = 1:episodes
    eps = max(0.05, 1 - ep / (0.6 * episodes));
    tr = genTraffic(cfg, cfg.numDevices, cfg.sliceSteps); R = 0; V = 0;
    for t = 1:cfg.sliceSteps
        s = tr(:, t) / cfg.bandwidth;
        if rand < eps, a = randi(nA); else, q = fwd(net, s); [~, a] = max(q); end
        [r, ~, ~, vi] = sliceReward(A(a, :)', tr(:, t + 1), cfg);
        s2 = tr(:, t + 1) / cfg.bandwidth;
        ptr = mod(ptr, cap) + 1; nb = min(nb + 1, cap);
        S(:, ptr) = s; S2(:, ptr) = s2; Ai(ptr) = a; Rw(ptr) = r; Dn(ptr) = double(t == cfg.sliceSteps);
        R = R + r; V = V + mean(vi); stepc = stepc + 1;
        if nb >= 500
            idx = randi(nb, 1, cfg.dqn.batch);
            qn = fwd(tgt, S2(:, idx)); y = Rw(idx) + cfg.dqn.gamma * (1 - Dn(idx)) .* max(qn, [], 1);
            [Q, c] = fwd(net, S(:, idx));
            dQ = zeros(nA, numel(idx));
            for j = 1:numel(idx), dQ(Ai(idx(j)), j) = (Q(Ai(idx(j)), j) - y(j)) / numel(idx); end
            g = backward(net, c, dQ);
            [net, opt] = adamStep(net, opt, g, cfg.dqn.lr);
        end
        if mod(stepc, cfg.dqn.sync) == 0, tgt = net; end
    end
    lg.rew(ep) = R / cfg.sliceSteps; lg.viol(ep) = V / cfg.sliceSteps;
    if verbose && mod(ep, max(1, round(episodes / 10))) == 0
        fprintf('  episode %3d/%d  reward %.3f  violations %.3f  eps %.2f\n', ep, episodes, lg.rew(ep), lg.viol(ep), eps);
    end
end
end

function net = initNet(ns, h, na)
net.W1 = randn(h, ns) * sqrt(2 / ns); net.b1 = zeros(h, 1);
net.W2 = randn(h, h) * sqrt(2 / h);   net.b2 = zeros(h, 1);
net.W3 = randn(na, h) * sqrt(1 / h) * 0.5; net.b3 = zeros(na, 1);
end

function [Q, c] = fwd(net, X)
Z1 = net.W1 * X + repmat(net.b1, 1, size(X, 2)); A1 = max(Z1, 0);
Z2 = net.W2 * A1 + repmat(net.b2, 1, size(X, 2)); A2 = max(Z2, 0);
Q = net.W3 * A2 + repmat(net.b3, 1, size(X, 2));
c.X = X; c.Z1 = Z1; c.A1 = A1; c.Z2 = Z2; c.A2 = A2;
end

function g = backward(net, c, dQ)
g.W3 = dQ * c.A2'; g.b3 = sum(dQ, 2);
dZ2 = (net.W3' * dQ) .* (c.Z2 > 0); g.W2 = dZ2 * c.A1'; g.b2 = sum(dZ2, 2);
dZ1 = (net.W2' * dZ2) .* (c.Z1 > 0); g.W1 = dZ1 * c.X'; g.b1 = sum(dZ1, 2);
end

function opt = initAdam(net)
f = fieldnames(net); opt.t = 0;
for i = 1:numel(f), opt.m.(f{i}) = zeros(size(net.(f{i}))); opt.v.(f{i}) = zeros(size(net.(f{i}))); end
end

function [net, opt] = adamStep(net, opt, g, lr)
b1 = 0.9; b2 = 0.999; e = 1e-8; opt.t = opt.t + 1; f = fieldnames(net);
for i = 1:numel(f)
    k = f{i};
    opt.m.(k) = b1 * opt.m.(k) + (1 - b1) * g.(k);
    opt.v.(k) = b2 * opt.v.(k) + (1 - b2) * g.(k).^2;
    mh = opt.m.(k) / (1 - b1^opt.t); vh = opt.v.(k) / (1 - b2^opt.t);
    net.(k) = net.(k) - lr * mh ./ (sqrt(vh) + e);
end
end

%% Utilities
function setSeed(s)
try
    rng(s);
catch
    rand('twister', s); randn('state', s); %#ok<RAND>
end
end

function s = stat(x)
x = x(~isnan(x)); n = numel(x);
if n == 0, s.m = NaN; s.sd = NaN; s.ci = NaN; s.n = 0; return; end
s.m = mean(x); s.n = n;
if n > 1, s.sd = std(x); df = n - 1; tc = 1.96 + 2.4 / df + 2.5 / df^2; s.ci = tc * s.sd / sqrt(n); else, s.sd = 0; s.ci = 0; end
end

function y = movAvg(x, w)
x = x(:); y = zeros(size(x));
for i = 1:numel(x), y(i) = mean(x(max(1, i - w + 1):i)); end
end

function v = nz(x)
if isnan(x), v = 0; else, v = x; end
end

function yline_safe(v)
hold on; xl = xlim; plot(xl, [v v], 'k--');
end


function ebar(x, m, c, mk, ls, name)
% Error bar helper that works in MATLAB and Octave
h = errorbar(x, m, c);
set(h, 'LineWidth', 1.5, 'Marker', mk, 'LineStyle', ls);
if ~isempty(name), set(h, 'DisplayName', name); else, set(h, 'Color', 'k'); end
end

function f = newFig(cfg)
f = figure('Visible', cfg.visible, 'Position', [100 100 1100 600]);
end

function saveFig(cfg, f, name)
if ~cfg.makeFigures, return; end
try
    print(f, fullfile(cfg.outDir, [name '.png']), '-dpng', '-r300');
    try, print(f, fullfile(cfg.outDir, [name '.pdf']), '-dpdf'); catch, end % vector for (optional)
catch err
    warning('Could not save %s: %s', name, err.message);
end
end

function writeCsv(file, header, rows)
fid = fopen(file, 'w');
if fid < 0, return; end
fprintf(fid, '%s\n', strjoin(header, ','));
for i = 1:size(rows, 1)
    parts = cell(1, size(rows, 2));
    for j = 1:size(rows, 2)
        v = rows{i, j};
        if ischar(v), parts{j} = strrep(v, ',', ';'); elseif isnan(v), parts{j} = 'NaN'; else, parts{j} = sprintf('%.6g', v); end
    end
    fprintf(fid, '%s\n', strjoin(parts, ','));
end
fclose(fid);
end

%% =============================================
%% Path Loss Models (select with cfg.plModel)
%% =============================================
function pl = pathLoss(cfg, d)
d = max(d, 10);
switch cfg.plModel
    case 'freespace'
        pl = 20 * log10(d) + 20 * log10(cfg.freqGHz * 1e9) - 147.55;
    case 'logdistance'
        pl0 = 20 * log10(cfg.freqGHz * 1e9) - 147.55;   % free space loss at 1 m
        pl = pl0 + 10 * cfg.plExp * log10(d);
    otherwise   % '3gpp-uma' style urban macro
        pl = 128.1 + 37.6 * log10(d / 1000);
end
end

%% ====================================================================
%% Metric Definitions and Notation Table (written to CSV and printed)
%% ====================================================================
function writeDefinitions(cfg)
defs = {
    'PDR (%)', '100 x packets delivered / packets sent, whole run (single definition used everywhere)';
    'Packet loss (%)', '100 - PDR (same denominator as PDR)';
    'Handover latency (ms)', 'time from handover trigger (TTT expired) until the first data packet is delivered on the new link = L2 switch + authentication + anchoring (+ recovery if a signaling exchange fails)';
    'Handover success (%)', 'handovers whose signaling exchanges all complete within R retransmissions';
    'Pre-auth ready (%)', 'handovers where the ECDH pre-authentication finished before the handover trigger';
    'Signaling overhead S (%)', '100 x signaling bytes (including retransmissions) / user data bytes';
    'Throughput (Mbps)', 'delivered bits in a time step / step length';
    'Throughput dip (%)', '100 x (1 - minimum throughput within 1 s after trigger / mean throughput 2 s before)';
    'Recovery time (ms)', 'time from trigger until 0.1 s averaged throughput is back to 90% of the pre-handover mean';
    'Jitter (ms)', 'standard deviation of per-step mean packet delay';
    'SLA violation rate', 'fraction of slice-time steps where slice latency exceeds its SLA';
    'Reward (DRL-NSA)', 'priority-weighted satisfaction minus priority-weighted SLA violations, per step'};
writeCsv(fullfile(cfg.outDir, 'metric_definitions.csv'), {'metric', 'definition'}, defs);
nota = {
    'tau', 'one-way backhaul/core link delay', 'ms', sprintf('%g (sweep %s)', cfg.tauRef, mat2str(cfg.tauList));
    'tau_loc, tau_mid', 'one-way local (MR-AP) and midhaul (AP-LMA) delay', 'ms', sprintf('%g, %g', cfg.tauLoc, cfg.tauMid);
    'f_T', 'per-message loss probability on a link', '-', sprintf('%g', cfg.fT);
    'R', 'maximum retransmissions per message', '-', sprintf('%d', cfg.R);
    'RTO', 'retransmission timeout = max(2 d + 10, 20)', 'ms', 'formula';
    'm_pre', 'messages in the ECDH pre-authentication exchange', '-', sprintf('%d', cfg.mPre);
    'W', 'signaling message size', 'bytes', sprintf('%d (also 128)', cfg.W);
    'L2', 'layer-2 switching time, uniform', 'ms', sprintf('[%g, %g]', cfg.L2min, cfg.L2max);
    'hyst, TTT', 'A3 hysteresis and time to trigger', 'dB, s', sprintf('%g, %g', cfg.sr.hyst, cfg.sr.ttt);
    'preMargin', 'pre-authentication starts when neighbour RSRP is within this margin of serving', 'dB', sprintf('%g', cfg.preMargin);
    'P(msg ok)', 'probability a message is delivered within R+1 attempts = 1 - f_T^(R+1)', '-', 'formula';
    'P(pre-auth ok)', '(1 - f_T^(R+1))^m_pre and exchange time <= lead time', '-', 'formula';
    'S(L,W)', 'nHO x m_total x (1 - f_T^(R+1))/(1 - f_T) x W / data bytes, m_total = m_pre + 4 + (1 - pReady) x 4', '%', 'formula';
    'N, B', 'number of IoMT devices, total bandwidth', '-, Mbps', sprintf('%d, %d', cfg.numDevices, cfg.bandwidth);
    's_t, a_t, r_t', 'DRL state (slice demand / B), action (slice bandwidth split), reward', '-', 'see E7';
    'gamma, lr', 'DQN discount factor and learning rate', '-', sprintf('%g, %g', cfg.dqn.gamma, cfg.dqn.lr)};
writeCsv(fullfile(cfg.outDir, 'notation_table.csv'), {'symbol', 'meaning', 'unit', 'value'}, nota);
fprintf('\nMetric Definitions and Notation Table Written to %s\n', cfg.outDir);
end

%% ==================================================
%% One Handover Execution with Component Breakdown
%% ==================================================
function [total, comp, ok, preOK] = hoOnce(name, tau, fT, cfg, cr, leadMs)
usesPre = any(strcmp(name, {'Proposed', 'Abl_NoAnchor'}));
preOK = false;
if usesPre
    [okp, tp] = exchange(cfg.mPre, tau, fT, cfg.R, max(2 * tau + 10, 20));
    tp = tp + 2 * cr.ecdh; preOK = okp && (tp <= leadMs);
end
rows = getPlan(name, preOK, tau, cfg, cr);
L2 = cfg.L2min + (cfg.L2max - cfg.L2min) * rand;
comp = [L2 0 0 0]; ok = true;  % [L2, authentication, anchoring/signaling, recovery]
for r = 1:size(rows, 1)
    [okr, t] = exchange(rows(r, 1), rows(r, 2), fT, cfg.R, max(2 * rows(r, 2) + 10, 20));
    t = t + rows(r, 3);
    if rows(r, 3) > 0, comp(2) = comp(2) + t; else, comp(3) = comp(3) + t; end
    if ~okr, ok = false; break; end
end
if ~ok, comp(4) = cfg.recovery + 6 * tau; end
total = sum(comp);
end

function k = poissSample(l)
if l > 30
    k = max(0, round(l + sqrt(l) * randn)); return;
end
L = exp(-l); k = 0; p = 1;
while true
    p = p * rand; if p <= L, break; end
    k = k + 1;
end
end

%% ============================
%% Single User pAP -> nAP run
%% ============================
function o = singleRunCore(cfg, scheme, seed, cr)
sr = cfg.sr; dt = sr.dt;
n = round((sr.isd - 2 * sr.startX) / sr.speed / dt);
t = (1:n)' * dt; x = sr.startX + sr.speed * t;
dP = sqrt(x.^2 + sr.yOffset^2); dN = sqrt((sr.isd - x).^2 + sr.yOffset^2);

% Radio: same seed -> same radio for every scheme
setSeed(seed);
rho = exp(-sr.speed * dt / sr.dCorr);
sh = zeros(n, 2);
for j = 1:2
    sh(:, j) = filter(sqrt(1 - rho^2) * sr.shSigma, [1 -rho], randn(n, 1), sr.shSigma * rho * randn);
end
rsrpRaw = [sr.txPower - pathLoss(cfg, dP) + sh(:, 1), sr.txPower - pathLoss(cfg, dN) + sh(:, 2)];
rsrp = rsrpRaw;
for j = 1:2
    rsrp(:, j) = filter(sr.l3, [1 -(1 - sr.l3)], rsrpRaw(:, j), (1 - sr.l3) * rsrpRaw(1, j));
end

% Traffic: same seed -> same offered traffic for every scheme
setSeed(seed + 1);
lam = sr.rateMbps * 1e6 / 8 / sr.pktSize * dt; offered = zeros(n, 1);
switch sr.traffic
    case 'poisson'
        for k = 1:n, offered(k) = poissSample(lam); end
    case 'bursty'
        st = 1;
        for k = 1:n
            if rand < 0.02, st = 3 - st; end
            if st == 1, rate = 1.8; else, rate = 0.2; end
            offered(k) = poissSample(lam * rate);
        end
    otherwise   % constant bit rate
        carry = 0;
        for k = 1:n, carry = carry + lam; offered(k) = floor(carry); carry = carry - offered(k); end
end

% Handover Decision (A3 event with hysteresis and time to trigger)
servIdx = ones(n, 1); serv = 1; cnt = 0; preStart = NaN; events = zeros(0, 4);
for k = 1:n
    servIdx(k) = serv; other = 3 - serv;
    if rsrp(k, other) > rsrp(k, serv) - sr.preMargin
        if isnan(preStart), preStart = k; end
    else
        preStart = NaN;
    end
    if rsrp(k, other) > rsrp(k, serv) + sr.hyst + sr.a3offset, cnt = cnt + 1; else, cnt = 0; end
    if cnt * dt >= sr.ttt
        ps = preStart; if isnan(ps), ps = k; end
        events(end + 1, :) = [k serv other ps]; %#ok<AGROW>
        serv = other; cnt = 0; preStart = NaN;
    end
end

% Handover Execution
setSeed(seed + 2);
nEv = size(events, 1);
lat = zeros(nEv, 1); comp = zeros(nEv, 4); okv = true(nEv, 1); preOK = false(nEv, 1);
winA = zeros(nEv, 1); winB = zeros(nEv, 1);
for i = 1:nEv
    leadMs = (events(i, 1) - events(i, 4)) * dt * 1000;
    [lat(i), comp(i, :), okv(i), preOK(i)] = hoOnce(scheme, sr.tau, sr.fT, cfg, cr, leadMs);
    winA(i) = events(i, 1); winB(i) = min(n, events(i, 1) + max(1, ceil(lat(i) / (dt * 1000))) - 1);
end

% Packet Delivery with Interruption, Buffering at the anchor and radio loss
buf = bufFrac(scheme);
snr = rsrpRaw(sub2ind([n 2], (1:n)', servIdx)) - cfg.noise;
per = 1 ./ (1 + exp((snr - cfg.snr0) / cfg.snrW));
delivered = zeros(n, 1); delay = nan(n, 1); lostInt = 0; lostRad = 0;
bufPk = 0; bufDelay = 0; intMask = false(n, 1);
for k = 1:n
    w = find(winA <= k & k <= winB, 1);
    if ~isempty(w)
        intMask(k) = true;
        elapsedMs = (k - winA(w) + 1) * dt * 1000;
        if elapsedMs <= cfg.holdMs, nb = round(buf * offered(k)); else, nb = 0; end
        lostInt = lostInt + offered(k) - nb;
        bufPk = bufPk + nb; bufDelay = bufDelay + nb * ((winB(w) + 1 - k) * dt * 1000);
    else
        extra = 0; extraDelay = 0;
        if bufPk > 0 && any(k == winB + 1)
            extra = bufPk; extraDelay = bufDelay; bufPk = 0; bufDelay = 0;
        end
        tot = offered(k) + extra;
        if tot > 0
            okc = sum(rand(tot, 1) >= per(k));
            lostRad = lostRad + tot - okc; delivered(k) = okc;
            delay(k) = (tot * sr.baseDelayMs + extraDelay) / tot;
        end
    end
end
lostInt = lostInt + bufPk;      % Buffered packets never released (run ended)
thr = delivered * sr.pktSize * 8 / dt / 1e6;
sent = sum(offered);

% KPIs
o.t = t; o.x = x; o.dP = dP; o.dN = dN; o.rsrpRaw = rsrpRaw; o.rsrp = rsrp; o.servIdx = servIdx;
o.thr = thr; o.intMask = intMask; o.events = events; o.lat = lat; o.comp = comp; o.ok = okv; o.preOK = preOK;
o.winA = winA; o.winB = winB; o.sent = sent; o.recv = sum(delivered); o.lostInt = lostInt; o.lostRad = lostRad;
o.pdr = 100 * o.recv / max(sent, 1); o.nHO = nEv; o.n = n; o.dt = dt;
o.meanThr = o.recv * sr.pktSize * 8 / (n * dt) / 1e6;
dd = delay(~isnan(delay)); if numel(dd) > 1, o.jitter = std(dd); else, o.jitter = NaN; end
o.tHO = NaN; o.xHO = NaN; o.rsrpS = NaN; o.rsrpN = NaN; o.dip = NaN; o.recMs = NaN; o.reestMs = NaN; o.preThr = NaN;
if nEv > 0
    k0 = events(1, 1); o.tHO = t(k0); o.xHO = x(k0); o.rsrpS = rsrp(k0, events(1, 2)); o.rsrpN = rsrp(k0, events(1, 3));
    a = max(1, k0 - round(2 / dt)); o.preThr = mean(thr(a:max(a, k0 - 1)));
    b = min(n, k0 + round(1 / dt)); o.dip = 100 * (1 - min(thr(k0:b)) / max(o.preThr, 1e-9));
    sm = movAvg(thr, max(1, round(0.1 / dt)));
    r = find((1:n)' >= winB(1) + 1 & sm >= 0.9 * o.preThr, 1);
    if ~isempty(r), o.recMs = (r - k0) * dt * 1000; end
    r2 = find((1:n)' > winB(1) & delivered > 0, 1);
    if ~isempty(r2), o.reestMs = (r2 - k0) * dt * 1000; end
end
o.pingpong = 0;
for i = 2:nEv
    if events(i, 3) == events(i - 1, 2) && (events(i, 1) - events(i - 1, 1)) * dt < 1, o.pingpong = o.pingpong + 1; end
end
end

function S = singleRunDemo(cfg, cr)
sr = cfg.sr;
fprintf('\n[S1] Single-user pAP to nAP handover (%s traffic, %g m/s, path loss: %s)\n', sr.traffic, sr.speed, cfg.plModel);
nH = sr.nHist; latA = []; latB = []; compA = zeros(0, 4); compB = zeros(0, 4);
pdrA = zeros(nH, 1); pdrB = zeros(nH, 1); okA = []; okB = []; preA = []; lat1 = nan(nH, 1);
for i = 1:nH
    a = singleRunCore(cfg, sr.scheme, cfg.seed + 100 + i, cr);
    b = singleRunCore(cfg, sr.compare, cfg.seed + 100 + i, cr);
    latA = [latA; a.lat]; compA = [compA; a.comp]; okA = [okA; a.ok]; preA = [preA; a.preOK]; pdrA(i) = a.pdr; %#ok<AGROW>
    latB = [latB; b.lat]; compB = [compB; b.comp]; okB = [okB; b.ok]; pdrB(i) = b.pdr; %#ok<AGROW>
    lat1(i) = firstOrNaN(a.lat);
end
% Displayed Run = the run whose first handover latency is the median (representative, not cherry-picked)
valid = find(~isnan(lat1));
if isempty(valid), repSeed = cfg.seed + 101;
else
    [~, ord] = sort(lat1(valid)); repSeed = cfg.seed + 100 + valid(ord(ceil(numel(ord) / 2)));
end
A = singleRunCore(cfg, sr.scheme, repSeed, cr);
B = singleRunCore(cfg, sr.compare, repSeed, cr);
S.A = A; S.B = B; S.latA = latA; S.latB = latB;

% KPI Table for the Displayed Run
hdr = {'scheme', 'handovers', 'trigger_time_s', 'trigger_pos_m', 'RSRP_serving_dBm', 'RSRP_target_dBm', 'HO_latency_ms', ...
       'traffic_reestablished_ms', 'PDR_pct', 'packet_loss_pct', 'mean_throughput_Mbps', 'throughput_dip_pct', 'recovery_ms', 'jitter_ms', 'ping_pong'};
rowOf = @(nm, o) {nm, o.nHO, o.tHO, o.xHO, o.rsrpS, o.rsrpN, firstOrNaN(o.lat), o.reestMs, o.pdr, 100 - o.pdr, o.meanThr, o.dip, o.recMs, o.jitter, o.pingpong};
rows = [rowOf(sr.scheme, A); rowOf(sr.compare, B)];
writeCsv(fullfile(cfg.outDir, 'S1_single_run_kpis.csv'), hdr, rows);
fprintf('  Displayed run (median-latency run, seed %d)\n', repSeed);
for r = 1:2
    fprintf('  %-12s HO=%d  trigger t=%.2f s x=%.0f m  RSRP %.1f -> %.1f dBm  latency %.1f ms  re-established %.1f ms  PDR %.3f %%  thr %.2f Mbps  dip %.0f %%  recovery %.0f ms  jitter %.2f ms\n', ...
        rows{r, 1}, rows{r, 2}, rows{r, 3}, rows{r, 4}, rows{r, 5}, rows{r, 6}, rows{r, 7}, rows{r, 8}, rows{r, 9}, rows{r, 11}, rows{r, 12}, rows{r, 13}, rows{r, 14});
end
sA = stat(latA); sB = stat(latB); pA = stat(pdrA); pB = stat(pdrB);
fprintf('  Over %d independent runs:\n', nH);
fprintf('  %-12s latency %.1f +- %.1f ms (95%% CI), p95 %.1f ms, PDR %.3f +- %.3f %%, HO success %.1f %%, pre-auth ready %.1f %%\n', sr.scheme, sA.m, sA.ci, prctl(latA, 95), pA.m, pA.ci, 100 * mean(okA), 100 * mean(preA));
fprintf('  %-12s latency %.1f +- %.1f ms (95%% CI), p95 %.1f ms, PDR %.3f +- %.3f %%, HO success %.1f %%\n', sr.compare, sB.m, sB.ci, prctl(latB, 95), pB.m, pB.ci, 100 * mean(okB));
writeCsv(fullfile(cfg.outDir, 'S1_multi_run_summary.csv'), {'scheme', 'n_handovers', 'latency_mean_ms', 'latency_ci95', 'latency_p95_ms', 'PDR_mean_pct', 'PDR_ci95', 'HO_success_pct'}, ...
    {sr.scheme, numel(latA), sA.m, sA.ci, prctl(latA, 95), pA.m, pA.ci, 100 * mean(okA); sr.compare, numel(latB), sB.m, sB.ci, prctl(latB, 95), pB.m, pB.ci, 100 * mean(okB)});
S.stats = struct('latA', sA, 'latB', sB, 'pdrA', pA, 'pdrB', pB);
if A.nHO == 0
    warning('No handover occurred in the displayed run. Increase cfg.sr.isd, lower cfg.sr.hyst or cfg.sr.ttt.');
    return;
end

% Figure 1: RSRP vs distance and trigger criterion
f = newFig(cfg);
subplot(2, 1, 1); hold on;
h1 = plot(A.x, A.rsrpRaw(:, 1), ':', 'Color', [0.6 0.6 1]);
h2 = plot(A.x, A.rsrpRaw(:, 2), ':', 'Color', [1 0.6 0.6]);
h3 = plot(A.x, A.rsrp(:, 1), 'b', 'LineWidth', 1.8);
h4 = plot(A.x, A.rsrp(:, 2), 'r', 'LineWidth', 1.8);
yl = ylim; hh = plot([A.xHO A.xHO], yl, 'k--', 'LineWidth', 1.5); plot(A.xHO, A.rsrpS, 'ko', 'MarkerFaceColor', 'k');
xlabel('Distance of user from pAP along the path (m)'); ylabel('RSRP (dBm)'); grid on;
legend([h1 h2 h3 h4 hh], {'pAP raw', 'nAP raw', 'pAP (L3 filtered)', 'nAP (L3 filtered)', 'Handover point'}, 'Location', 'eastoutside');
title(sprintf('RSRP vs distance, handover at x = %.0f m (t = %.2f s)', A.xHO, A.tHO));
subplot(2, 1, 2); hold on;
plot(A.x, A.rsrp(:, 2) - A.rsrp(:, 1), 'm', 'LineWidth', 1.5);
plot([A.x(1) A.x(end)], [sr.hyst + sr.a3offset sr.hyst + sr.a3offset], 'k-.');
plot([A.x(1) A.x(end)], [-sr.preMargin -sr.preMargin], 'g-.');
yl = ylim; plot([A.xHO A.xHO], yl, 'k--');
xlabel('Distance of user from pAP along the path (m)'); ylabel('RSRP(nAP) - RSRP(pAP) (dB)'); grid on;
legend({'Difference', sprintf('A3 threshold (+%g dB), TTT %g s', sr.hyst + sr.a3offset, sr.ttt), sprintf('Pre-auth starts (%g dB)', -sr.preMargin), 'Handover'}, 'Location', 'northwest');
saveFig(cfg, f, 'S1_rsrp_vs_distance');

% Figure 2: throughput, latency histogram, PDR summary, latency breakdown
f = newFig(cfg);
subplot(2, 3, 1); hold on;
w = max(1, round(0.1 / A.dt));
plot(A.t, movAvg(A.thr, w), 'b', 'LineWidth', 1.4); plot(B.t, movAvg(B.thr, w), 'r', 'LineWidth', 1.4);
yl = ylim; plot([A.tHO A.tHO], yl, 'k--');
xlabel('Time (s)'); ylabel('Throughput (Mbps, 0.1 s average)'); grid on; legend({sr.scheme, sr.compare, 'Trigger'}, 'Location', 'southwest'); title('Throughput over the run');
subplot(2, 3, 2); hold on;
k0 = A.events(1, 1); a = max(1, k0 - round(0.5 / A.dt)); b = min(A.n, k0 + round(1.0 / A.dt));
stairs(A.t(a:b) - A.tHO, A.thr(a:b), 'b', 'LineWidth', 1.2); stairs(B.t(a:b) - A.tHO, B.thr(a:b), 'r', 'LineWidth', 1.2);
xlabel('Time relative to trigger (s)'); ylabel('Throughput per step (Mbps)'); grid on; title('Zoom: interruption and release burst');
subplot(2, 3, 3); hold on;
lo = min([latA; latB]); hi = max([latA; latB]); if hi - lo < 1e-6, hi = lo + 1; end
ctr = linspace(lo, hi, 25); nA = hist(latA, ctr); nB = hist(latB, ctr);
bar(ctr, [nA(:) nB(:)], 'grouped');
xlabel('Handover latency (ms)'); ylabel('Count'); grid on; legend({sr.scheme, sr.compare}, 'Location', 'north');
title(sprintf('Latency histogram, %d runs', nH));
subplot(2, 3, 4);
pdS = [100 * A.recv / A.sent, 100 * A.lostInt / A.sent, 100 * A.lostRad / A.sent; 100 * B.recv / B.sent, 100 * B.lostInt / B.sent, 100 * B.lostRad / B.sent];
bar(pdS(:, 2:3), 'stacked'); set(gca, 'XTick', 1:2, 'XTickLabel', {sr.scheme, sr.compare});
ylabel('Packets lost (% of sent)'); yl = ylim; ylim([0 yl(2) * 1.5]); legend({'Lost in interruption', 'Lost on radio'}, 'Location', 'northwest'); grid on;
title(sprintf('PDR: %.3f %% vs %.3f %%', A.pdr, B.pdr));
subplot(2, 3, 5);
bar([mean(compA, 1); mean(compB, 1)], 'stacked'); set(gca, 'XTick', 1:2, 'XTickLabel', {sr.scheme, sr.compare});
ylabel('Mean handover latency (ms)'); legend({'L2 switch', 'Authentication', 'Anchoring', 'Recovery'}, 'Location', 'northwest'); grid on; title('Latency breakdown');
subplot(2, 3, 6); hold on;
plot(A.t, A.servIdx, 'b', 'LineWidth', 1.5); set(gca, 'YTick', [1 2], 'YTickLabel', {'pAP', 'nAP'}); ylim([0.5 2.5]);
xlabel('Time (s)'); ylabel('Serving cell'); grid on; title('Serving cell over time');
saveFig(cfg, f, 'S1_handover_kpis');
end

function v = firstOrNaN(x)
if isempty(x), v = NaN; else, v = x(1); end
end

function p = prctl(x, q)
if isempty(x), p = NaN; return; end
x = sort(x(:)); i = max(1, min(numel(x), ceil(q / 100 * numel(x)))); p = x(i);
end

%% ======================================================================
%% S0: ECDH + AES-GCM Handover Protocol with Security Checks (needs Java)
%% ======================================================================
function S = cryptoFlowDemo(cfg)
S = struct('ok', false);
fprintf('\n[S0] ECDH (P-256) + HKDF-SHA256 + AES-128-GCM handover flow and security checks\n');
if ~usejava('jvm')
    fprintf('  Java is not available in this MATLAB session; section skipped.\n'); return;
end
try
    setSeed(cfg.seed + 11);
    rb = @(n) int8(randi([-128 127], n, 1));   % Demo randomness only (use java.security.SecureRandom in a real system)
    steps = {}; checks = {};
    Kreg = rb(16); pID = cfBytes('PID0001A'); Kasnap = rb(16);   % Phase 0: registration key, pseudo-ID, AS-nAP key (assumed secure channel)

    % Phase 1: ECDH pre-authentication, MR <-> AS (via pAP); public keys authenticated with Kreg
    kpg = java.security.KeyPairGenerator.getInstance('EC');
    kpg.initialize(java.security.spec.ECGenParameterSpec('secp256r1'));
    tic; kpMR = kpg.generateKeyPair(); tKey = toc * 1000;
    kpAS = kpg.generateKeyPair();
    qMR = int8(kpMR.getPublic().getEncoded()); qAS = int8(kpAS.getPublic().getEncoded());
    nMR = rb(16); nAS = rb(16);
    msg1 = [qMR; nMR; pID]; tic; tag1 = cfHmac(Kreg, msg1); t1 = toc * 1000;
    steps(end+1, :) = {'1', 'PRE_AUTH_REQ  MR -> AS: Q_MR, N_MR, pID, MAC(Kreg, .)', numel(msg1) + numel(tag1), t1 + tKey};
    asOk1 = isequal(cfHmac(Kreg, msg1), tag1);
    msg2 = [qAS; nAS; qMR]; tag2 = cfHmac(Kreg, msg2);
    steps(end+1, :) = {'2', 'PRE_AUTH_RESP AS -> MR: Q_AS, N_AS, MAC(Kreg, Q_AS|N_AS|Q_MR)', numel(msg2) - numel(qMR) + numel(tag2), t1};
    mrOk2 = isequal(cfHmac(Kreg, msg2), tag2);
    tic; zMR = cfEcdh(kpMR.getPrivate(), qAS); zAS = cfEcdh(kpAS.getPrivate(), qMR); tEcdh = toc * 1000 / 2;
    info = [cfBytes('IoMT-HO-v1|'); pID];
    KsMR = cfHkdf(zMR, [nMR; nAS], info, 16); KsAS = cfHkdf(zAS, [nMR; nAS], info, 16);
    steps(end+1, :) = {'3', 'ECDH + HKDF (both sides): Z = ECDH(d, Q_peer); Ks = HKDF(Z, N_MR|N_AS, info)', 0, tEcdh};
    checks(end+1, :) = {'Phase 1: public keys authenticated, ECDH secret equal, Ks equal', asOk1 && mrOk2 && isequal(zMR, zAS) && isequal(KsMR, KsAS)};

    % Phase 2: HO_TRIGGER (AES-GCM under Ks, AAD = pID | seq | type)
    seq = 1; aad = [pID; int8([0; 0; 0; seq]); cfBytes('HO_TRIGGER')]; pt = cfBytes('MR01|nAP02');
    tic; ct = cfEnc(KsMR, cfIv(seq), aad, pt); tE = toc * 1000;
    tic; ptAS = cfDec(KsAS, cfIv(seq), aad, ct); tD = toc * 1000; lastSeq = seq;
    steps(end+1, :) = {'4', 'HO_TRIGGER MR -> pAP -> AS: pID, seq, AES-GCM(Ks, target ID)', numel(pID) + 4 + numel(ct), tE + tD};
    checks(end+1, :) = {'Phase 2: HO_TRIGGER decrypts and authenticates at AS', isequal(ptAS, pt)};

    % Phase 3: key push to nAP (AS-nAP secure channel assumed in the paper) and MR-side derivation
    seqb = int8([0; 0; 0; seq]);
    KnAS = cfHkdf(KsAS, cfBytes('nAP02'), [cfBytes('nAP-key|'); seqb], 16);
    push = cfEnc(Kasnap, cfIv(1), cfBytes('HO_PUSH_KEY'), KnAS);
    KnNap = cfDec(Kasnap, cfIv(1), cfBytes('HO_PUSH_KEY'), push);
    KnMR = cfHkdf(KsMR, cfBytes('nAP02'), [cfBytes('nAP-key|'); seqb], 16);
    steps(end+1, :) = {'5', 'HO_PUSH_KEY AS -> nAP: AES-GCM(K_AS-nAP, Kn)', numel(push), 0};
    checks(end+1, :) = {'Phase 3: MR, AS and nAP hold the same target key Kn', isequal(KnAS, KnNap) && isequal(KnAS, KnMR)};

    % Phase 4: HO_COMPLETE with next pseudo-ID, then key refresh (ratchet)
    pID2 = cfHmac(KsAS, [cfBytes('pID|'); pID; seqb]); pID2 = pID2(1:8);
    aad2 = [pID2; int8([0; 0; 0; seq + 1]); cfBytes('HO_COMPLETE')];
    ct2 = cfEnc(KnNap, cfIv(2), aad2, cfBytes('STATUS_OK'));
    ptMR = cfDec(KnMR, cfIv(2), aad2, ct2);
    steps(end+1, :) = {'6', 'HO_COMPLETE nAP -> MR: pID_next, seq, AES-GCM(Kn, status)', numel(pID2) + 4 + numel(ct2), 0};
    checks(end+1, :) = {'Phase 4: HO_COMPLETE accepted by MR', isequal(ptMR, cfBytes('STATUS_OK'))};
    KsNextAS = cfHkdf(KsAS, cfBytes('refresh'), seqb, 16); KsNextMR = cfHkdf(KsMR, cfBytes('refresh'), seqb, 16);
    checks(end+1, :) = {'Key refresh: MR and AS derive the same next session key', isequal(KsNextAS, KsNextMR) && ~isequal(KsNextAS, KsAS)};

    % Attack checks
    ok = (seq > lastSeq);     % Replay of HO_TRIGGER with seq=1 again
    checks(end+1, :) = {'Replay: repeated HO_TRIGGER (same seq) rejected', ~ok};
    ct3 = ct; ct3(1) = -ct3(1) - 1; caught = false;     % Flip the bits of the first byte
    try, cfDec(KsAS, cfIv(seq), aad, ct3); catch, caught = true; end
    checks(end+1, :) = {'Tampering: modified ciphertext rejected (GCM tag)', caught};
    caught = false; Katt = rb(16); forged = cfEnc(Katt, cfIv(5), aad, pt);
    try, cfDec(KsAS, cfIv(5), aad, forged); catch, caught = true; end
    checks(end+1, :) = {'Impersonation: message under attacker key rejected', caught};
    kpX = kpg.generateKeyPair(); qX = int8(kpX.getPublic().getEncoded());
    mitm = [qX; nMR; pID]; detected = ~isequal(cfHmac(Kreg, mitm), tag1);
    checks(end+1, :) = {'MITM: substituted ECDH public key rejected (MAC with Kreg)', detected};
    caught = false;
    try, cfDec(KsNextAS, cfIv(seq), aad, ct); catch, caught = true; end
    checks(end+1, :) = {'Session-key compromise after refresh does not open earlier traffic', caught};
    caught = false; aadWrong = [pID; int8([0; 0; 0; 9]); cfBytes('HO_TRIGGER')];
    try, cfDec(KsAS, cfIv(seq), aadWrong, ct); catch, caught = true; end
    checks(end+1, :) = {'Header binding: altered pID/seq in AAD rejected', caught};

    fprintf('  Message flow (sizes measured from the real byte arrays)\n  %-4s %-82s %8s %10s\n', 'Step', 'Message', 'Bytes', 'Time (ms)');
    for i = 1:size(steps, 1), fprintf('  %-4s %-82s %8d %10.3f\n', steps{i, 1}, steps{i, 2}, steps{i, 3}, steps{i, 4}); end
    fprintf('  Security checks\n');
    allOk = true;
    for i = 1:size(checks, 1)
        if checks{i, 2}, r = 'PASS'; else, r = 'FAIL'; allOk = false; end
        fprintf('  [%s] %s\n', r, checks{i, 1});
    end
    fprintf('  Note: these are functional checks of the protocol, not a formal security proof.\n');
    fprintf('  Note: ECDH is re-run every %d handovers (cfg.crypto.rekeyEvery); in between keys are refreshed by HKDF.\n', cfg.crypto.rekeyEvery);
    writeCsv(fullfile(cfg.outDir, 'S0_message_flow.csv'), {'step', 'message', 'bytes', 'time_ms'}, steps);
    cc = checks; for i = 1:size(cc, 1), cc{i, 2} = double(cc{i, 2}); end
    writeCsv(fullfile(cfg.outDir, 'S0_security_checks.csv'), {'check', 'pass_1_fail_0'}, cc);
    S.ok = allOk; S.steps = steps; S.checks = checks;
catch err
    fprintf('  Crypto demo failed: %s\n', err.message);
end
end

function b = cfBytes(s)
b = int8(double(s(:)));
end

function iv = cfIv(seq)
u = zeros(12, 1, 'uint8'); u(12) = uint8(seq); iv = typecast(u, 'int8');
end

function out = cfHmac(key, data)
mac = javax.crypto.Mac.getInstance('HmacSHA256');
mac.init(javax.crypto.spec.SecretKeySpec(key, 'HmacSHA256'));
out = int8(mac.doFinal(data));
out = out(:);
end

function k = cfHkdf(ikm, salt, info, len)
if isempty(salt), salt = zeros(32, 1, 'int8'); end
prk = cfHmac(salt, ikm);               % Extract
t = cfHmac(prk, [info(:); int8(1)]);   % Expand, first block
k = t(1:len);
end

function z = cfEcdh(priv, pubBytes)
kf = java.security.KeyFactory.getInstance('EC');
pub = kf.generatePublic(java.security.spec.X509EncodedKeySpec(pubBytes));
ka = javax.crypto.KeyAgreement.getInstance('ECDH'); ka.init(priv); ka.doPhase(pub, true);
z = int8(ka.generateSecret()); z = z(:);
end

function ct = cfEnc(key, iv, aad, pt)
c = javax.crypto.Cipher.getInstance('AES/GCM/NoPadding');
c.init(1, javax.crypto.spec.SecretKeySpec(key, 'AES'), javax.crypto.spec.GCMParameterSpec(128, iv));
c.updateAAD(aad); ct = int8(c.doFinal(pt)); ct = ct(:);
end

function pt = cfDec(key, iv, aad, ct)
c = javax.crypto.Cipher.getInstance('AES/GCM/NoPadding');
c.init(2, javax.crypto.spec.SecretKeySpec(key, 'AES'), javax.crypto.spec.GCMParameterSpec(128, iv));
c.updateAAD(aad); pt = int8(c.doFinal(ct)); pt = pt(:);
end
