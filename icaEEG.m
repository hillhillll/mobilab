% Definition of the class icaEEG. This class serves as a placeholder for ICA
% analysis of EEG data. It derives from the class eeg incorporating the 
% traditional ICA fields in EEGLAB software.
%
%
% For more details visit: https://code.google.com/p/mobilab/ 
%
% Author: Alejandro Ojeda, SCCN, INC, UCSD, Apr-2011

classdef icaEEG < eeg & icaFields
    methods
        function obj = icaEEG(header)
            % Creates an icaEEG object.
            % 
            % Input arguments:
            %       header:   header file (string)
            % 
            % Output argument:
            %       obj:      icaEEG object (handle)
            
            if nargin < 1, error('Not enough input arguments.');end
            obj@eeg(header);
            obj@icaFields(header);
        end
        %%
        function jsonObj = serialize(obj)
            metadata = saveobj(obj);
            metadata.size = size(obj);
            metadata.event = obj.event.uniqueLabel;
            metadata.artifactMask = sum(metadata.artifactMask(:) ~= 0);
            metadata.writable = double(metadata.writable);
            metadata.history = obj.history;
            metadata.sessionUUID = char(obj.sessionUUID);
            metadata.uuid = char(obj.uuid);
            if ~isempty(metadata.channelSpace),  metadata.hasChannelSpace = 'yes'; else metadata.hasChannelSpace = 'no';end
            if ~isempty(metadata.leadFieldFile), metadata.hasLeadField    = 'yes'; else metadata.hasLeadField    = 'no';end
            if ~isempty(obj.fiducials) &&  ~isempty(obj.surfaces) && ~isempty(obj.atlas)
                 metadata.hasHeadModel = 'yes';
            else metadata.hasHeadModel = 'no';
            end
            if ~isempty(obj.icawinv) &&  ~isempty(obj.icasphere) && ~isempty(obj.icaweights)
                 metadata.hasICA = 'yes';
            else metadata.hasICA = 'no';
            end
            metadata = rmfield(metadata,{'parentCommand' 'timeStamp' 'hardwareMetaData' 'channelSpace' 'leadFieldFile' 'fiducials' 'surfaces' 'atlas' 'icawinv' 'icasphere' 'icaweights'});
            jsonObj  = savejson('',metadata,'ForceRootName', false);
        end
        %%
        function hFigure = plotScalpMap(obj,scalpmap)
            % Plots an ICA scalp map onto the surface of the scalp.
            % 
            % Input argument:
            %       scalpMap:  column of obj.icainv to plot
            % 
            % Output argument:
            %       hFigure:   handle to the fugure

            if nargin < 2, error('Not enough input arguments.');end
            if isempty(obj.channelSpace) || isempty(obj.label) || isempty(obj.surfaces);
                error('Head model is incomplete or missing.');
            end
            if scalpmap == -1
                prompt = {'Component to plot'};
                num_lines = 1;
                def = {'1'};
                varargin = inputdlg2(prompt,'',num_lines,def);
                if isempty(varargin), return;end
                varargin{1} = eval(varargin{1});
                if isnan(varargin{1}), return;end
                scalpmap = varargin{1};
            end
            Ns = length(scalpmap);
            if Ns > 1
                for it=1:Ns, hFigure = plotScalpMap(obj,scalpmap(it));end
                return
            end
            load(obj.surfaces);
            W = geometricTools.localGaussianInterpolator(obj.channelSpace,surfData(1).vertices);
            data = W*obj.icawinv(:,scalpmap);
            color = obj.container.container.preferences.gui.backgroundColor;
            
            hFigure = figure('Menubar','figure','ToolBar','figure','renderer','opengl','Visible','on','Position',[947 509 682 420],'Color',color,'Name','MoBILAB plotScalpMap');
            hAxes = axes('Parent',hFigure);
            patch('vertices',surfData(1).vertices,'faces',surfData(1).faces,'FaceVertexCData',data,...
                'FaceColor','interp','FaceLighting','phong','LineStyle','none','FaceAlpha',1,'Parent',hAxes);
            camlight(0,180)
            camlight(0,0)
            axis(hAxes,'equal');
            axis(hAxes,'off')
            mx = max(abs(data));
            set(hAxes,'Clim',[-mx mx]);
            title(hAxes,{texlabel(obj.name,'literal'),[' IC' num2str(scalpmap)]});
        end
        %%
        function topoPlot(obj,scalpmap)
            % Calls EGGLAB's topoplot (legacy code)
            %
            % Input argument:
            %       scalpMap: columns of obj.icainv to plot

            if isempty(obj.channelSpace) || isempty(obj.label), error('Electrode locations are missing.');end
            
            EEG = obj.EEGstructure(false,false);
            if nargin < 2 || scalpmap(1) == -1
                pop_topoplot(EEG,0);
                return
            end
            if nargin < 2, scalpmap = 1:obj.numberOfChannels;end
            if ~any(ismember(1:obj.numberOfChannels,scalpmap)), error('Index exceeds matrix dimensions.');end
            pop_topoplot(EEG,0,scalpmap);
        end
        %%
        function hFigure = topoPlot3D(obj,scalpmap,interpMethod)
            % As EEGLAB's topoplot but in 3D. It uses the scalp surface to 
            % plot the topographies.
            % 
            % Input argument:
            %       scalpMap: columns of obj.icainv to plot
            %
            % Output arguments:
            %       hFigure: handle to the fugure

            if isempty(obj.channelSpace) || isempty(obj.label) || isempty(obj.surfaces), error('Head model is missing.');end
            if scalpmap(1) == -1
                prompt = {'Interpolation method (''spline'', ''linear'' or ''ridge'')','Components to plot:'};
                dlg_title = 'topoPlot';
                num_lines = 2;
                def = {'linear',['1:' num2str(obj.numberOfChannels)]};
                varargin = inputdlg2(prompt,dlg_title,num_lines,def);
                if isempty(varargin), return;end
                interpMethod = varargin{1};
                scalpmap = eval(['[' varargin{2} ']']);
                if any(isnan(scalpmap)), return;end
            end
            if nargin < 2, scalpmap = 1:obj.numberOfChannels;end
            if ~exist('interpMethod','var'), interpMethod = 'linear';end
            if ~any(ismember(1:obj.numberOfChannels,scalpmap)), error('Index exceeds matrix dimensions.');end
            % warning('I''m sorry, I''m testing this function now. Alejandro.')
            N = length(scalpmap);
            Nr = ceil(sqrt(N/sqrt(2)));
            Nc = real(Nr+round(sqrt(N-Nr^2)));
            
            load(obj.surfaces);
            sensorsOn = imread([obj.container.container.path filesep 'skin' filesep 'sensorsOn.png']);
            sensorsOff = imread([obj.container.container.path filesep 'skin' filesep 'sensorsOff.png']);
            
            % T = DelaunayTri(obj.channelSpace(:,1),obj.channelSpace(:,2),obj.channelSpace(:,3));
            % [K,AV] = convexHull(T);
            % figure;trisurf(K,T.X(:,1),T.X(:,2),T.X(:,3))
                       
            % D = geometricTools.getDistance(surfData(1).vertices,obj.channelSpace);
            % mn = min(D,[],2);
            % I = mn > 23;
            
            % figure
            % skinColor = [1,.75,.65];
            % patch('vertices',surfData(1).vertices,'faces',surfData(1).faces,'FaceColor',skinColor,'FaceLighting','phong',...
            %     'LineStyle','none','FaceAlpha',1,'SpecularColorReflectance',0,'SpecularExponent',50,'SpecularStrength',0.5);
            % camlight(0,180);camlight(0,0);
            
            hSensors = zeros(N,1);
            hFigure = figure('Color',obj.container.container.preferences.gui.backgroundColor);
            toolbarHandle = findall(hFigure,'Type','uitoolbar');
            hcb = uitoggletool(toolbarHandle,'CData',sensorsOff,'Separator','off','HandleVisibility','off','TooltipString','Sensors On/Off','userData',{sensorsOn,sensorsOff},'State','off');
            set(hcb,'OnCallback',@(src,event)sensorsOnOff(hFigure,hcb,'sensorsOn'),'OffCallback',@(src, event)sensorsOnOff(hFigure,hcb,'sensorsOff'));
            
            for it=1:N-1
                h = subplot(Nr,Nc,it);
                set(h,'ButtonDownFcn',@copyaxis)
                ICi = geometricTools.interpOnSurface(surfData(1).vertices,surfData(1).faces,obj.channelSpace,obj.icawinv(:,scalpmap(it)),interpMethod);
                % ICi(I) = nan;
                patch('vertices',surfData(1).vertices,'faces',surfData(1).faces,'FaceVertexCData',ICi,'FaceColor','interp','FaceLighting','phong',...
                'LineStyle','none','FaceAlpha',1,'SpecularColorReflectance',0,'SpecularExponent',50,'SpecularStrength',0.5,'Parent',h,'ButtonDownFcn','copyaxis;rotate3d');
                maxAbsolute = max(abs(ICi));
                caxis(h,[-maxAbsolute maxAbsolute]);
                camlight(0,180);camlight(0,0);
                hold(h,'on')
                hSensors(it) = scatter3(obj.channelSpace(:,1),obj.channelSpace(:,2),obj.channelSpace(:,3),'filled','MarkerEdgeColor','k','MarkerFaceColor','y','Parent',h,'ButtonDownFcn','copyaxis;rotate3d');
                view(h,[-90 90])
                title(h,['IC' num2str(scalpmap(it))])
                axis(h,'off')
                axis(h,'equal')
                drawnow
            end
            h = subplot(Nr,Nc,N);
            ICi = geometricTools.interpOnSurface(surfData(1).vertices,surfData(1).faces,obj.channelSpace,obj.icawinv(:,scalpmap(N)),interpMethod);
            % ICi(I) = nan;
            patch('vertices',surfData(1).vertices,'faces',surfData(1).faces,'FaceVertexCData',ICi,'FaceColor','interp','FaceLighting','phong',...
                'LineStyle','none','FaceAlpha',1,'SpecularColorReflectance',0,'SpecularExponent',50,'SpecularStrength',0.5,'Parent',h,'ButtonDownFcn','copyaxis;rotate3d');
            %colormap(bipolar(512, 0.99));
            maxAbsolute = max(abs(ICi));
            caxis(h,[-maxAbsolute maxAbsolute]);
            camlight(0,180);camlight(0,0)
            hold(h,'on')
            hSensors(N) = scatter3(obj.channelSpace(:,1),obj.channelSpace(:,2),obj.channelSpace(:,3),'filled','MarkerEdgeColor','k','MarkerFaceColor','y','Parent',h,'ButtonDownFcn','copyaxis;rotate3d');
            set(hSensors,'Visible','off');
            view(h,[-90 90])
            title(h,['IC' num2str(scalpmap(N))])
            axis(h,'off')            
            axis(h,'equal')
            set(hFigure,'userData',hSensors);
        end
        %%
        function EEG = EEGstructure(obj,ismmf,passData)
            % Returns the equivalent EEG (EEGLAB) structure. It calls the 
            % same method in its base class adding then ICA fields.
            
            if nargin < 2, ismmf = false;end
            if nargin < 3, passData = true;end
            s = dbstack;
            isCalledFromGui = any(~cellfun(@isempty,strfind({s.name},'myDispatch')));
            
            indexEEG = obj.container.gObj.getAncestors(obj.container.findItem(obj.uuid)+1)-1;
            indexEEG(indexEEG == 0) = [];
            indexEEG = max(indexEEG);
            if isempty(indexEEG)
                EEG = EEGstructure@eeg(obj,ismmf,passData);
                icachansind = 1:obj.numberOfChannels;
            else
                EEG = obj.container.item{indexEEG}.EEGstructure(ismmf,passData);
                [~,icachansind] = ismember(obj.label,obj.container.item{indexEEG}.label,'legacy');
                icachansind(icachansind==0) = [];
            end
            EEG.icawinv = obj.icawinv;
            EEG.icasphere = obj.icasphere;
            EEG.icaweights = obj.icaweights;
            EEG.icachansind = icachansind;
            if ismmf && passData, pop_saveset( EEG, EEG.filename,EEG.filepath);end
            if isCalledFromGui
                try ALLEEG = evalin('base','ALLEEG');
                catch ALLEEG = [];%#ok
                end
                [ALLEEG,EEG,CURRENTSET] = eeg_store(ALLEEG, EEG);
                assignin('base','ALLEEG',ALLEEG);
                assignin('base','CURRENTSET',CURRENTSET);
                assignin('base','EEG',EEG);
                evalin('base','eeglab redraw');
            end
        end
        %%
        function [J,fvu,aic,viewerObj] = estimateScalpMapPCD(obj,scalpmap,plotFlag,threshold)
            % Computes the posterior distribution of the Primary Current Density given an 
            % ICA scalp map. See the help section of the function variationalDynLoreta.
            % 
            % Input arguments:
            %       scalpmap: indices of the scalp maps to invert
            %       plotFlag,threshold
            %
            % Output arguments:
            %       J:         Primary Current Density, size number of verices in the cortical
            %                  surface by number of scalp maps
            %       viewerObj: 
            % 
            % Usage:
            %       eegObj  = mobilab.allStreams.item{ eegItem };
            %       latency = 512:1024; % some latencies of interest
            %       J = eegObj.estimatePCD(latency);

            dispCommand = false;
            if nargin < 2, error('Specify the scalpmap you want to localize.');end
            if nargin < 3, plotFlag = true;end
            if nargin < 4, threshold = [20 80];end
            
            if isempty(obj.channelSpace) || isempty(obj.label) || isempty(obj.surfaces);
                error('Head model is incomplete or missing.');
            end
            if isempty(obj.atlas), error('Individual atlas is missing.');end
            if isempty(obj.leadFieldFile), error('Lead field is missing.');end
            if isnumeric(scalpmap) && scalpmap(1) == -1
                prefObj = [...
                    PropertyGridField('scalpmap',1:size(obj.icawinv,1),'DisplayName','Scalp map','Description','Scalp map you want to estimate the sources of.')...
                    PropertyGridField('plotFlag',true,'DisplayName','Plot GCV','Description','Plot the Generalized Cross Validation function. The GCV is the criteria used to optimize the regularization parameter. The minimum of the curve represents the less complex model that better fits the data.')...
                    PropertyGridField('threshold',[20 80],'DisplayName','Threshold','DisplayName','Percentiles in the empirical distribution of the source map used in the correction for multiples comparison.')...
                    ];
                
                hFigure = figure('MenuBar','none','Name','Eestimate scalp map source','NumberTitle', 'off','Toolbar', 'none','Units','pixels','Color',obj.container.container.preferences.gui.backgroundColor,...
                    'Resize','off','userData',0);
                position = get(hFigure,'position');
                set(hFigure,'position',[position(1:2) 303 231]);
                hPanel = uipanel(hFigure,'Title','','BackgroundColor','white','Units','pixels','Position',[0 55 303 180],'BorderType','none');
                g = PropertyGrid(hPanel,'Properties', prefObj,'Position', [0 0 1 1]);
                uicontrol(hFigure,'Position',[72 15 70 21],'String','Cancel','ForegroundColor',obj.container.container.preferences.gui.fontColor,...
                    'BackgroundColor',obj.container.container.preferences.gui.buttonColor,'Callback',@cancelCallback);
                uicontrol(hFigure,'Position',[164 15 70 21],'String','Ok','ForegroundColor',obj.container.container.preferences.gui.fontColor,...
                    'BackgroundColor',obj.container.container.preferences.gui.buttonColor,'Callback',@okCallback);
                uiwait(hFigure);
                if ~ishandle(hFigure), return;end
                if ~get(hFigure,'userData'), close(hFigure);return;end
                close(hFigure);
                drawnow
                val = g.GetPropertyValues();
                scalpmap = val.scalpmap;
                plotFlag = val.plotFlag;
                threshold = val.threshold;
                dispCommand = true;
            end
            if ~any(ismember(1:size(obj.icawinv,1),scalpmap)), error('Wrong scalpmap');end
            if dispCommand
                disp('Running:');
                fprintf('  mobilab.allStreams.item{%i}.estimateScalpMapPCD( [ %s ], %i, [%s]);\n',obj.container.findItem(obj.uuid),num2str(scalpmap),plotFlag,num2str(threshold));
            end
            
            nlambdas = 100;
            
            % opening the surfaces by the Thalamus
            structName = {'Thalamus_L' 'Thalamus_R'};
            [~,K,L,rmIndices] = getSourceSpace4PEB(obj,structName);
            indexAncestors = obj.container.gObj.getAncestors(obj.container.findItem(obj.uuid)+1)-1;
            indexAncestors(indexAncestors == 0) = [];
            eegIndices = obj.container.getItemIndexFromItemClass('eeg');
            I = ismember( eegIndices,indexAncestors);
            eegIndices = eegIndices(I);
            [~,loc] = min(abs(eegIndices - obj.container.findItem(obj.uuid)));
                        
            load(obj.surfaces);
            n = size(surfData(end).vertices,1); %#ok
            ind = setdiff(1:n,rmIndices);
            
            % W = geometricTools.localGaussianInterpolator(obj.channelSpace,eegObj.channelSpace,16,4);
            % Y =  W*obj.icawinv(:,scalpmap);
            %-
            % Y(I,:) = obj.icawinv(:,scalpmap);
            Y = obj.icawinv(:,scalpmap);
            %-
            
            % removing the average reference
            %H = eye(eegObj.numberOfChannels) - ones(eegObj.numberOfChannels)/eegObj.numberOfChannels;
            ny = length(Y);
            H = eye(ny) - ones(ny)/n;
            Y = H*Y;
            Yr = Y;
            K = H*K;
            Y(end,:) = [];
            K(end,:) = [];
            dim = size(K);
            Ns = length(scalpmap);
            hasDirection = n == dim(2)/3+length(rmIndices);
            if hasDirection
                J = zeros(n*3,Ns);
                tmp = zeros(n,3);
                tmp(ind,:) = 1;
                tmp = tmp(:);
                ind = find(tmp);
            else
                J = zeros(n,Ns);
            end
            viewerObj = [];
            %--
            [U,S,V] = svd(K/L,'econ');
            Ut = U';
            s2 = diag(S).^2;
            iLV = L\V;
            %--
            fvu = zeros(Ns,1);
            aic = zeros(Ns,1);
            obj.initStatusbar(1,Ns,'Estimating PCD...');
            for it=1:Ns
               %J(ind,it) = inverseSolutionLoreta(Y(:,it),K,L,nlambdas,plotFlag,threshold);
               %J(ind,it) = dynamicLoreta(Ut,Y(:,it),s2,V,iLV,L);
               [J(ind,it),~,~,~,~,fvu(it),aic(it)] = variationalDynLoreta(Ut,Y(:,it),s2,iLV,L);
               if ~isempty(threshold)
                   if hasDirection
                       t = J(ind,it);
                       n1 = n-length(rmIndices);
                       t = reshape(t,[n1 3]);
                       t = sqrt(sum(t.^2,2));
                       t = t./std(t);
                       th = prctile(t,threshold(end));
                       I = t<th;
                       indZero = false(n1,3);
                       indZero(I,:) = true;
                       indZero = indZero(:);
                   else
                       t = J(ind,it);
                       th = prctile(t,threshold);
                       indZero = t>th(1) & t<th(end);
                   end
                   J(ind(indZero),it) = 0;
               end
               obj.statusbar(it);
            end
            if plotFlag, viewerObj = obj.plotOnModel(J,Yr,[obj.name ' PCD: ICs ' num2str(scalpmap)]);end
        end
        %%
        function indices = extractBrainComponents(obj, max_fvu, plotFlag) 
            if nargin < 2, max_fvu = 0.1;end
            if max_fvu < 0, max_fvu = 0.1;plotFlag = true;end
            if ~exist('plotFlag','var'), plotFlag = false;end
            [~,fvu] = obj.estimateScalpMapPCD(1:obj.numberOfChannels, 0, []);
            indices = find(fvu <= max_fvu);
            if plotFlag && ~isempty(indices), topoPlot(obj,indices);end
        end
        %%
        function [J,models]= icaModelSelection(obj,latency)
            if isempty(obj.channelSpace) || isempty(obj.label) || isempty(obj.surfaces);
                error('Head model is incomplete or missing.');
            end
            if isempty(obj.atlas), error('Individual atlas is missing.');end
            if isempty(obj.leadFieldFile), error('Lead field is missing.');end
            
            structName = 'Thalamus';
            [sourceSpace,K,L] = getSourceSpace4PEB(obj,structName);
            
            indexAncestors = obj.container.gObj.getAncestors(obj.container.findItem(obj.uuid)+1)-1;
            indexAncestors(indexAncestors == 0) = [];
            indexAncestors = sort(indexAncestors,'descend');
            for it=1:length(indexAncestors)
                if isa(obj.container.item{indexAncestors(it)},'eeg'), break;end
            end
            eegObj = obj.container.item{indexAncestors(it)};
            indices = eegObj.getTimeIndex(latency);
            % data = eegObj.data;
            % data = zscore(data);
            % Y = data(indices,:)';
            % clear data;
            
            n = size(eegObj.channelSpace,1)-1;
            W = geometricTools.localGaussianInterpolator(eegObj.channelSpace(1:end-1,:),obj.channelSpace,3,3);
            Q = W'*obj.icawinv;%*W;
            %--
            Y = Q(:,9);
            %--
            % Q1 = zeros([n n 1+size(Q,2)]);
            % for it=1:size(Q,2), Q1(:,:,it+1) = diag(diag((Q(:,it)*Q(:,it)')/(n-1)));end
            Q1(:,:,1) = trace((Y*Y')/(n-1))*eye(n);
            
            % removing the average reference
            H = eye(eegObj.numberOfChannels) - ones(eegObj.numberOfChannels)/eegObj.numberOfChannels;
            % Y = H*Y;
            K = H*K;
            % Y(end,:) = [];
            K(end,:) = [];
            
            [J,m] = invertParametricEmpiricalBayes(Y,K,Q1,L,-4,12,eegObj,sourceSpace);
        end
    end
    methods(Hidden)
        %%
        function properyArray = getPropertyGridField(obj)
            properyArray1 = getPropertyGridField@eeg(obj);
            properyArray2 = getPropertyGridField@icaFields(obj);
            properyArray = [properyArray1 properyArray2];
        end
        %%
        function jmenu = contextMenu(obj)
            jmenu = javax.swing.JPopupMenu;
            %--
            menuItem = javax.swing.JMenuItem('Add sensor locations');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'loadElectrodeWizard',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Create head model');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'buildHeadModelFromTemplate',-1});
            jmenu.add(menuItem);
            %---------
            menuItem = javax.swing.JMenuItem('Compute lead field matrix');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'computeLeadFieldBEM',-1});
            jmenu.add(menuItem);
            %---------
            jmenu.addSeparator;
            %---------
            menuItem = javax.swing.JMenuItem('Filter');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'filter',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Clean line');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'cleanLine',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('ICA');
            % set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'filter',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Time frequency analysis (CWT)');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'continuousWaveletTransform',-1});
            jmenu.add(menuItem);
            %---------
            % menuItem = javax.swing.JMenuItem('Time frequency analysis (STFT)');
            % set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'shortTimeFourierTransform',-1});
            % jmenu.add(menuItem);
            %---------
            menuItem = javax.swing.JMenuItem('Estimate scalp map primary current density');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'estimateScalpMapPCD',-1});
            jmenu.add(menuItem);
            %---------
            menuItem = javax.swing.JMenuItem('Extract brain components');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'extractBrainComponents',-1});
            jmenu.add(menuItem);
            %---------
            jmenu.addSeparator;
            %---------
            menuItem = javax.swing.JMenuItem('Plot');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'dataStreamBrowser',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Plot spectrum');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'spectrum',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Plot on scalp');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'plotOnScalp',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Show head model');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'plotHeadModel',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('ICA scalp maps (EEGLAB''s topoplot)');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'topoPlot',-1});
            jmenu.add(menuItem);
            %---------
            menuItem = javax.swing.JMenuItem('ICA scalp maps 3D');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'topoPlot3D',-1});
            jmenu.add(menuItem);
            %---------
            jmenu.addSeparator;
            %---------
            menuItem = javax.swing.JMenuItem('Inspect');
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'inspect',-1});
            jmenu.add(menuItem);
            %--
            menuItem = javax.swing.JMenuItem('Export to EEGLAB');
            jmenu.add(menuItem);
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj,'EEGstructure',0});
            %--
            menuItem = javax.swing.JMenuItem('Annotation');
            jmenu.add(menuItem);
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@annotation_Callback,obj});
            %--
            menuItem = javax.swing.JMenuItem('Generate batch script');
            jmenu.add(menuItem);
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@generateBatch_Callback,obj});
            %--
            menuItem = javax.swing.JMenuItem('<HTML><FONT color="maroon">Delete object</HTML>');
            jmenu.add(menuItem);
            set(handle(menuItem,'CallbackProperties'), 'ActionPerformedCallback', {@myDispatch,obj.container,'deleteItem',obj.container.findItem(obj.uuid)});
        end
    end
end

%----
function sensorsOnOff(hFigure,hObject,opt)
hSensors = get(hFigure,'userData');
CData = get(hObject,'userData');
if isempty(strfind(opt,'Off'))
    set(hObject,'CData',CData{2});
else
    set(hObject,'CData',CData{1});
end
if strcmp(opt,'sensorsOn')
    set(hSensors,'Visible','on');
else
    set(hSensors,'Visible','off');
end
end