function [net,meta] = rawArchitecture(kind,K,N)
%RAWARCHITECTURE Fixed small nominal-amplitude CNN or causal residual TCN.
kind=upper(string(kind));
assert(isscalar(kind) && any(kind==["CNN" "TCN"]),'eba:RawKind','Raw architecture must be CNN or TCN.');
assert(isscalar(K) && isfinite(K) && K>=2 && K==fix(K) && isscalar(N) && isfinite(N) && N>=31 && N==fix(N), ...
    'eba:RawArchitecture','Class count and sequence length must be positive supported integers.');
input=sequenceInputLayer(1,'Normalization','none','MinLength',N,'Name','input');
if kind=="CNN"
    layers=[input
        convolution1dLayer(31,8,'Stride',10,'Padding','same','Name','conv1')
        reluLayer('Name','relu1')
        convolution1dLayer(7,16,'Stride',2,'Padding','same','Name','conv2')
        reluLayer('Name','relu2')
        convolution1dLayer(5,32,'Stride',2,'Padding','same','Name','conv3')
        reluLayer('Name','relu3')
        globalAveragePooling1dLayer('Name','pool')
        fullyConnectedLayer(K,'Name','logits')
        softmaxLayer('Name','probabilities')];
    net=dlnetwork(layers); receptiveField=31+6*10+4*20; stride=40;
    expectedParameters=3760+33*K; causal=false;
else
    net=dlnetwork;
    net=addLayers(net,[input
        convolution1dLayer(31,8,'Stride',10,'Padding','causal','Name','embedding')
        reluLayer('Name','embedding_relu')]);
    previous="embedding_relu";
    for b=1:7
        prefix="block"+b; dilation=2^(b-1);
        block=[convolution1dLayer(3,8,'DilationFactor',dilation,'Padding','causal','Name',char(prefix+"_conv1"))
            reluLayer('Name',char(prefix+"_relu1"))
            dropoutLayer(.1,'Name',char(prefix+"_drop1"))
            convolution1dLayer(3,8,'DilationFactor',dilation,'Padding','causal','Name',char(prefix+"_conv2"))
            reluLayer('Name',char(prefix+"_relu2"))
            dropoutLayer(.1,'Name',char(prefix+"_drop2"))
            additionLayer(2,'Name',char(prefix+"_add"))
            reluLayer('Name',char(prefix+"_out"))];
        net=addLayers(net,block);
        net=connectLayers(net,previous,prefix+"_conv1");
        net=connectLayers(net,previous,prefix+"_add/in2");
        previous=prefix+"_out";
    end
    net=addLayers(net,[globalAveragePooling1dLayer('Name','pool')
        fullyConnectedLayer(K,'Name','logits')
        softmaxLayer('Name','probabilities')]);
    net=connectLayers(net,previous,'pool'); net=initialize(net);
    receptiveField=31+2*(3-1)*sum(2.^(0:6))*10; stride=10;
    expectedParameters=3056+9*K; causal=true;
end
parameters=sum(cellfun(@numel,net.Learnables.Value));
assert(parameters==expectedParameters && parameters<10000,'eba:RawParameters','Unexpected architecture parameter count.');
meta=struct('kind',char(kind),'architecture_version','raw_fixed_v1','n_classes',K,'input_channels',1, ...
    'sequence_samples',N,'input_normalization','none','input_units','nominal_pu_rms','input_data_format','CTB', ...
    'output_data_format','BC','learnable_parameters',parameters,'local_receptive_field_samples',receptiveField, ...
    'effective_sample_stride',stride,'prediction_context_samples',N,'causal_feature_stack',causal, ...
    'incremental_inference_implemented',false,'global_average_pooling',true, ...
    'proposal_status','fixed_engineering_architecture_no_test_tuning');
end
