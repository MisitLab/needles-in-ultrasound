% Visualization of stored data: echogenicity.
% Author: Nick J. van de Berg
% Date: 01-12-2017

% Inputs.
load ech_collected_data.mat v;
fields = fieldnames(v);
last_field = cell2mat(fields(end,1));                                       % Requires sequential order of structure fields.
last_vid_nr = str2double(last_field(4:end));

% Needle types to show.
ShownPerSubplot = {1:2,3:4,5:6,[7,9]};                                      % Needle indices compared in each subplot (as defined below).
subplots = length(ShownPerSubplot);                                         % Nr. of supplots.
ndl_sel = {'Steel_1mm', 'Steel_2mm', ...                                    % Needle names as used during data collection.
    'Steel_rough_2mm', 'Niti_2mm', ...     
    'Steel_1cut_2mm', 'Steel_2cut_2mm', ...                               
    'Bevel_22G', 'RFA_2mm', ...                                             
    'Trocar_18G'};
ndl_tags = {'Steel-p 1mm', 'Steel-p 2mm', ...                               % Corresponding needle names as used in article/images.
    'Steel-sb 2mm', 'Niti-u 2mm', ...            
    'Steel-edm1 2mm', 'Steel-edm2 2mm', ...                               
    'Chiba-u 22G', 'RFA_2mm', ...      
    'Trocar-u 18G'};
col_vec = {[0 0 255]; [200 200 255]; ...                                    % RGB colour channels, associated to each needle.
    [255 200 200]; [255 0 0]; ...
    [0 255 0]; [200 255 200]; ...
    [255 200 255]; [120 80 50]; ...
    [255 0 255]};  
col_vec = cellfun(@(x) x/255,col_vec,'un',0);
% Note: RFA needles were not tested in this part of the experiment.

%% Load data...
len_ang = length(v.vid1.outputs.CNR_tip);
len_ndl = length(ndl_sel);
SR_tip = cell(len_ang,len_ndl);
SR_sha = cell(len_ang,len_ndl);
SR_tip_rev = cell(len_ang,len_ndl);
i_builder = 1; % Table builder index.
for index = 1:last_vid_nr
    fn = strcat('vid',num2str(index)); % Recreate fieldname.
    try
        for n = 1:9
            ECs2{i_builder,n} = v.(fn).inputs.ECs{n}; %#ok<SAGROW>
        end
        ECs2{i_builder,10} = v.(fn).inputs.angles;
        [~,pos] = ismember(ECs2{i_builder,1},ndl_sel);
        ECs2{i_builder,11} = pos;

        % Output data: acquire signal ratios (SR).   
        for i = 1:len_ang
            SR_tip{i,pos} = [SR_tip{i,pos}, v.(fn).outputs.CNR_tip(i)]; 
            SR_sha{i,pos} = [SR_sha{i,pos}, v.(fn).outputs.CNR_shaft(i)]; 
            try
                SR_tip_rev{i,pos} = [SR_tip_rev{i,pos}, ...
                    v.(fn).outputs_rev.CNR_tip(end-i+1)]; 
            catch
            end
        end
        % If file data exists: +1 to table builder index.
        i_builder = i_builder+1;
    catch
    end
end

%% Compute summary metrics.

% Medians and standard deviations.
SR_sha_med = cellfun(@median,SR_sha);
SR_sha_std = cellfun(@std,SR_sha);
SR_tip_med = cellfun(@median,SR_tip);
SR_tip_std = cellfun(@std,SR_tip);
SR_tipr_med = cellfun(@median,SR_tip_rev);
SR_tipr_std = cellfun(@std,SR_tip_rev);

% Median +/- std margins.
SR_sha_plus = SR_sha_med + SR_sha_std;
SR_sha_min = SR_sha_med - SR_sha_std;
SR_tip_plus = SR_tip_med + SR_tip_std;
SR_tip_min = SR_tip_med - SR_tip_std;
SR_tipr_plus = SR_tipr_med + SR_tipr_std;
SR_tipr_min = SR_tipr_med - SR_tipr_std;

% Apply rotations, counterclockwise angular rotation.
rot_ang = pi*(180-v.(fn).inputs.angles)/180; 
for i2 = 1:len_ang
    rot_mat = [cos(rot_ang(i2)), sin(rot_ang(i2)); ...
        -sin(rot_ang(i2)), cos(rot_ang(i2))];
    t1 = rot_mat.*[1;0];
    x_fact(i2) = t1(1,1); %#ok<SAGROW>
    y_fact(i2) = t1(1,2); %#ok<SAGROW>
end

tip_med_x = SR_tip_med.*x_fact'; 
tip_plus_x = SR_tip_plus.*x_fact'; 
tip_min_x = SR_tip_min.*x_fact'; 
sha_med_x = SR_sha_med.*x_fact';
sha_plus_x = SR_sha_plus.*x_fact';
sha_min_x = SR_sha_min.*x_fact';
tipr_med_x = SR_tipr_med.*x_fact'; 
tipr_plus_x = SR_tipr_plus.*x_fact'; 
tipr_min_x = SR_tipr_min.*x_fact'; 

tip_med_y = SR_tip_med.*y_fact';
tip_plus_y = SR_tip_plus.*y_fact';
tip_min_y = SR_tip_min.*y_fact';
sha_med_y = SR_sha_med.*y_fact';
sha_plus_y = SR_sha_plus.*y_fact';
sha_min_y = SR_sha_min.*y_fact';
tipr_med_y = SR_tipr_med.*y_fact';
tipr_plus_y = SR_tipr_plus.*y_fact';
tipr_min_y = SR_tipr_min.*y_fact';

% Show data shafts.
patch_a = 0.4; % Alpha value (transparantie) of patches.
figure('units','normalized','outerposition',[0 0 1 1]), hold on,
max_v = 1; % Max. value on radial axis.
for sp = 1:subplots
    subplot(2,2,sp)
    title('Polar plot of needle shaft echogenicity versus insertion angle.')
    xlabel('Insertion angle [degrees]');
    ylabel('SR (echogenicity, shaft) [-]');
    xlim([-(max_v+.1),(max_v+.1)]); ylim([0,(max_v+.1)]);
    line(x_fact,y_fact,'LineWidth',2,'Color','k',...
        'HandleVisibility','off');
    line(0.25*x_fact,0.25*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(0.5*x_fact,0.5*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(0.75*x_fact,0.75*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line([x_fact(1),0,1],[y_fact(1),0,0],'LineWidth',2,'Color','k',...
        'HandleVisibility','off');
    for i3 = 2:len_ang-1
        line([0,x_fact(i3)],[0,y_fact(i3)],'LineStyle','-.','Color','k',...
            'HandleVisibility','off');
    end
    text(-1.01,.44,'25'); text(-0.03,1.05,'90'); text(1.015,0.03,'180');
    for ndls = ShownPerSubplot{sp}
        patch([sha_plus_x(:,ndls);flipud(sha_min_x(:,ndls))],...
            [sha_plus_y(:,ndls);flipud(sha_min_y(:,ndls))],col_vec{ndls},...
            'FaceAlpha',0.4);
        line(sha_med_x(:,ndls),sha_med_y(:,ndls),'Color','k',...
            'HandleVisibility','off');
    end
    [~,h_legend] = legend(ndl_tags{ShownPerSubplot{sp}});
    PatchInLegend = findobj(h_legend, 'type', 'patch');
    for ptch_count = 1:length(ShownPerSubplot{sp})
        set(PatchInLegend(ptch_count), 'FaceAlpha', patch_a);
    end
end

% Show data tips.
figure('units','normalized','outerposition',[0 0 1 1]), hold on,
for sp = 1:subplots
    subplot(2,2,sp)
    title('Polar plot of needle tip echogenicity versus insertion angle.')
    xlabel('Insertion angle [degrees]');
    ylabel('SR (echogenicity, tip) [-]');
    xlim([-(max_v+.1),(max_v+.1)]); ylim([0,(max_v+.1)]);
    line(x_fact,y_fact,'LineWidth',2,'Color','k',...
        'HandleVisibility','off');
    line(0.25*x_fact,0.25*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(0.5*x_fact,0.5*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(0.75*x_fact,0.75*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line([x_fact(1),0,1],[y_fact(1),0,0],'LineWidth',2,'Color','k',...
        'HandleVisibility','off');
    for i3 = 2:len_ang-1
        line([0,x_fact(i3)],[0,y_fact(i3)],'LineStyle','-.','Color','k',...
            'HandleVisibility','off');
    end
    text(-1.01,.44,'25'); text(-0.03,1.05,'90'); text(1.015,0.03,'180');
    for ndls = ShownPerSubplot{sp}
        patch([tip_plus_x(:,ndls);flipud(tip_min_x(:,ndls))],...
            [tip_plus_y(:,ndls);flipud(tip_min_y(:,ndls))],col_vec{ndls},...
            'FaceAlpha',0.4);
        line(tip_med_x(:,ndls),tip_med_y(:,ndls),'Color','k',...
            'HandleVisibility','off');
%         if ndls == 7 % Check 'backside' of bevel tips.
%             patch([tipr_plus_x(:,ndls);flipud(tipr_min_x(:,ndls))],...
%                 [tipr_plus_y(:,ndls);flipud(tipr_min_y(:,ndls))],'r')
%             line(tipr_med_x(:,ndls),tipr_med_y(:,ndls),'Color','k');
%         end
    end
    [~,h_legend] = legend(ndl_tags{ShownPerSubplot{sp}});
    PatchInLegend = findobj(h_legend, 'type', 'patch');
    for ptch_count = 1:length(ShownPerSubplot{sp})
        set(PatchInLegend(ptch_count), 'FaceAlpha', patch_a);
    end
end