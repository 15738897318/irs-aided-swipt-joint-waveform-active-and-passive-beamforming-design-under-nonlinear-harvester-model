function [infoWaveform, powerWaveform, infoRatio, powerRatio, current, rate] = waveform_sdr(infoWaveform, powerWaveform, infoRatio, powerRatio, beta2, beta4, txPower, noisePower, rateConstraint, tolerance, compositeChannel, nCandidates)
    % Function:
    %   - optimize the information and power waveform to maximize the R-E region
    %   - compute the output DC current and user rate
    %
    % Input:
    %   - infoWaveform (w_I) [nSubbands]: weight on information carriers (in the previous iteration)
    %   - powerWaveform (w_P) [nSubbands]: weight on power carriers (in the previous iteration)
    %   - infoRatio (\bar{\rho}): information splitting ratio (in the previous iteration)
    %   - powerRatio (\rho): power splitting ratio (in the previous iteration)
    %   - beta2: coefficients on second-order current terms
    %   - beta4: coefficients on fourth-order current terms
    %   - txPower (P): transmit power constraint
    %   - noisePower (\sigma_n^2): average noise power
    %   - rateConstraint (\bar{R}): user rate constraint
    %   - tolerance (\epsilon): minimum gain ratio per iteration
    %   - compositeChannel (h) [nSubbands * nTxs * nRxs]: the composite channel
    %   - nCandidates (Q): number of CSCG random vectors to generate
    %
    % Output:
    %   - infoWaveform (w_I) [nSubbands]: weight on information carriers
    %   - powerWaveform (w_P) [nSubbands]: weight on power carriers
    %   - infoRatio (\bar{\rho}): information splitting ratio
    %   - powerRatio (\rho): power splitting ratio
    %   - current: maximum achievable output DC current
    %   - rate: maximum achievable user rate
    %
    % Comment:
    %   - solve SDR problem to obtain high-rank waveform outer product matrices
    %   - use Gaussian randomization method to extract waveform vectors
    %
    % Author & Date: Yang (i@snowztail.com) - 31 May 20



    % * Initialize algorithm
    nSubbands = size(infoWaveform, 1);
    % \boldsymbol{H}_{I/P}
    channelMatrix = compositeChannel * compositeChannel';
    % \boldsymbol{H}_{I/P,n}
    channelCoefMatrix = cell(2 * nSubbands - 1, 1);
    for iSubband = - nSubbands + 1 : nSubbands - 1
        channelCoefMatrix{iSubband + nSubbands} = diag(diag(channelMatrix, iSubband), iSubband);
    end
    % \boldsymbol{W}_{I/P}^{(0)}
    infoMatrix = infoWaveform * infoWaveform';
    powerMatrix = powerWaveform * powerWaveform';
    infoAuxiliary = zeros(2 * nSubbands - 1, 1);
    powerAuxiliary = zeros(2 * nSubbands - 1, 1);
    % t'_{I/P,n}^{(0)}
    for iSubband = - nSubbands + 1 : nSubbands - 1
        infoAuxiliary(iSubband + nSubbands) = trace(conj(channelCoefMatrix{iSubband + nSubbands}) * infoMatrix);
        powerAuxiliary(iSubband + nSubbands) = trace(conj(channelCoefMatrix{iSubband + nSubbands}) * powerMatrix);
    end
    % \boldsymbol{A}^{(0)}
    infoCoefMatrix = zeros(nSubbands);
    powerCoefMatrix = zeros(nSubbands);
    % a^{(0)}, b^{(0)}
    aLowerBound = powerRatio ^ 2;
    bLowerBound = infoAuxiliary(nSubbands) * powerAuxiliary(nSubbands);

    % * SCA
    current_ = 0;
    isConverged = false;
    while ~isConverged
        % * Update solution, auxiliary, and SDR matrices
        infoRatio_ = infoRatio;
        powerRatio_ = powerRatio;
        infoMatrix_ = infoMatrix;
        powerMatrix_ = powerMatrix;
        infoAuxiliary_ = infoAuxiliary;
        powerAuxiliary_ = powerAuxiliary;
        infoCoefMatrix_ = infoCoefMatrix;
        powerCoefMatrix_ = powerCoefMatrix;
        aLowerBound_ = aLowerBound;
        bLowerBound_ = bLowerBound;
        % \boldsymbol{A}_{I/P}^{(i)}
        infoCoefMatrix = (1 / 2 * beta2) * conj(channelCoefMatrix{nSubbands}) + (3 / 2 * beta4) * powerRatio_ * infoAuxiliary_(nSubbands) * conj(channelCoefMatrix{nSubbands});
        powerCoefMatrix = (1 / 2 * beta2) * conj(channelCoefMatrix{nSubbands});
        for iSubband = - nSubbands + 1 : nSubbands - 1
            powerCoefMatrix = powerCoefMatrix + (3 / 8 * beta4) * powerRatio_ * (conj(powerAuxiliary_(iSubband + nSubbands)) * conj(channelCoefMatrix{iSubband + nSubbands}) ...
                + powerAuxiliary_(iSubband + nSubbands) * transpose(channelCoefMatrix{iSubband + nSubbands}));
        end

        % * Solve high-rank outer product matrix by CVX
        cvx_begin quiet
            cvx_precision high
            cvx_solver mosek
            variable infoMatrix(nSubbands, nSubbands) hermitian semidefinite;
            variable powerMatrix(nSubbands, nSubbands) hermitian semidefinite;
            variable infoRatio nonnegative;
            variable powerRatio nonnegative;
            variable aLowerBound nonnegative;
            variable bLowerBound nonnegative;
            expression infoAuxiliary(2 * nSubbands - 1, 1);
            expression powerAuxiliary(2 * nSubbands - 1, 1);
            expression signalPower(nSubbands, 1);
            expression sinr(nSubbands, 1);
            % t'_{I/P,n}
            for iSubband = - nSubbands + 1 : nSubbands - 1
                infoAuxiliary(iSubband + nSubbands) = trace(conj(channelCoefMatrix{iSubband + nSubbands}) * infoMatrix);
                powerAuxiliary(iSubband + nSubbands) = trace(conj(channelCoefMatrix{iSubband + nSubbands}) * powerMatrix);
            end
            % \tilde{z}'
            currentLowerBound = (1 / 2) * (powerRatio_ + trace(infoCoefMatrix_ * infoMatrix_)) * (powerRatio + trace(infoCoefMatrix * infoMatrix)) - (1 / 4) * (powerRatio - trace(infoCoefMatrix * infoMatrix)) ^ 2 ...
                + (1 / 2) * real(powerRatio_ + trace(powerCoefMatrix_ * powerMatrix_)) * (powerRatio + trace(powerCoefMatrix * powerMatrix)) - (1 / 4) * (powerRatio - trace(powerCoefMatrix * powerMatrix)) ^ 2 ...
                + (1 / 2) * (aLowerBound_ + bLowerBound_) * (aLowerBound + bLowerBound) - (1 / 4) * (aLowerBound - bLowerBound) ^ 2;
            % g
            for iSubband = 1 : nSubbands
                signalPower(iSubband) = (1 / 2) * (infoRatio_ + infoMatrix_(iSubband, iSubband)) * (infoRatio + infoMatrix(iSubband, iSubband)) ...
                    - (1 / 4) * (infoRatio_ + infoMatrix_(iSubband, iSubband)) ^ 2 - (1 / 4) * (infoRatio - infoMatrix(iSubband, iSubband)) ^ 2;
            end
            % \gamma
            for iSubband = 1 : nSubbands
                sinr(iSubband) = signalPower(iSubband) * square_abs(compositeChannel(iSubband)) / noisePower;
            end
            % a
            a = 2 * powerRatio_ * powerRatio - powerRatio_ ^ 2;
            % b
            b = (1 / 2) * (infoAuxiliary_(nSubbands) + powerAuxiliary_(nSubbands)) * (infoAuxiliary(nSubbands) + powerAuxiliary(nSubbands)) ...
                - (1 / 4) * (infoAuxiliary_(nSubbands) + powerAuxiliary_(nSubbands)) ^ 2 - (1 / 4) * (infoAuxiliary(nSubbands) - powerAuxiliary(nSubbands)) ^ 2;
            maximize currentLowerBound;
            subject to
                (1 / 2) * (trace(infoMatrix) + trace(powerMatrix)) <= txPower;
                geo_mean(1 + sinr) >= 2 ^ (rateConstraint / nSubbands);
                powerRatio + infoRatio <= 1;
                a >= aLowerBound;
                b >= bLowerBound;
        cvx_end

        % * Update output current
        % z
        current = real((1 / 2) * beta2 * powerRatio * (infoAuxiliary(nSubbands) + powerAuxiliary(nSubbands)) ...
            + (3 / 8) * beta4 * powerRatio ^ 2 * (2 * infoAuxiliary(nSubbands) ^ 2 + (powerAuxiliary' * powerAuxiliary)) ...
            + (3 / 2) * beta4 * powerRatio ^ 2 * infoAuxiliary(nSubbands) * powerAuxiliary(nSubbands));
        % R
        rate = 0;
        for iSubband = 1 : nSubbands
            rate = rate + log2(1 + infoRatio * infoMatrix(iSubband, iSubband) * square_abs(compositeChannel(iSubband)) / noisePower);
        end

        % * Test convergence
        isConverged = abs(current - current_) / current <= tolerance;
        current_ = current;
    end
    infoMatrix = full(infoMatrix);
    powerMatrix = full(powerMatrix);

    % * Recover rank-1 solution by randomization method
    [u1, sigma1] = eig(infoMatrix);
    [u2, sigma2] = eig(powerMatrix);
    current = 0;
    rate = 0;
    for iCandidate = 1 : nCandidates
        % \boldsymbol{w}_{I/P,q}
        infoWaveform_ = u1 * sigma1 ^ (1 / 2) * exp(1i * 2 * pi * rand(nSubbands, 1));
        powerWaveform_ = u2 * sigma2 ^ (1 / 2) * exp(1i * 2 * pi * rand(nSubbands, 1));
        % \boldsymbol{W}_{I/P,q}
        infoMatrix = infoWaveform_ * infoWaveform_';
        powerMatrix = powerWaveform_ * powerWaveform_';
        % t'_{I/P,n}
        for iSubband = - nSubbands + 1 : nSubbands - 1
            infoAuxiliary(iSubband + nSubbands) = trace(conj(channelCoefMatrix{iSubband + nSubbands}) * infoMatrix);
            powerAuxiliary(iSubband + nSubbands) = trace(conj(channelCoefMatrix{iSubband + nSubbands}) * powerMatrix);
        end
        % z
        current_ = real((1 / 2) * beta2 * powerRatio * (infoAuxiliary(nSubbands) + powerAuxiliary(nSubbands)) ...
            + (3 / 8) * beta4 * powerRatio ^ 2 * (2 * infoAuxiliary(nSubbands) ^ 2 + (powerAuxiliary' * powerAuxiliary)) ...
            + (3 / 2) * beta4 * powerRatio ^ 2 * infoAuxiliary(nSubbands) * powerAuxiliary(nSubbands));
        % R
        rate_ = 0;
        for iSubband = 1 : nSubbands
            rate_ = rate_ + log2(1 + infoRatio * infoMatrix(iSubband, iSubband) * square_abs(compositeChannel(iSubband)) / noisePower);
        end
        if current_ >= current && rate_ >= rateConstraint
            current = current_;
            rate = rate_;
            infoWaveform = infoWaveform_;
            powerWaveform = powerWaveform_;
        end
    end

end
