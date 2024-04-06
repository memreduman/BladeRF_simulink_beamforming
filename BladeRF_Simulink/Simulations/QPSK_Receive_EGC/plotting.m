%qpsktxrx = QPSK_short_EGC_BER_graph_init();
EbNoVec = (16:2:30); 
snrdB = 30;
EbNo = 10;

% Reset the error and bit counters
% Estimate the BER
simout = sim('QPSK_short_EGC_BER_graph.slx');
%simout_old = simout.ber;
%berEst(i) = double(simout.ber(1));
%i=i+1;
%fprintf('EbNo=%d\n',n);

%berTheory = berawgn(EbNoVec,'psk',4,'nondiff');
%semilogy(EbNoVec,berEst,'*')
%hold on
%semilogy(EbNoVec,berTheory)
%grid
%legend('Estimated BER','Theoretical BER')
%xlabel('Eb/No (dB)')
%ylabel('Bit Error Rate')

plot(simout.ber.time,simout.ber.signals.values(:,2))
xlabel('Time')
ylabel('Total number of errors')
xlim([0 1])
hold on
plot(simout_old.time,simout_old.signals.values(:,2))
legend('with 2 Receiver with EGC','with 1 Receiver')
title('Receive Diversity')