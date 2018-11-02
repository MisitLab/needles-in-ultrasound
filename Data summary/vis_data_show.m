% Visualization of stored data: visibility.
% Author: Nick J. van de Berg
% Date: 01-12-2017

% Inputs.
load vis_collected_data.mat v;
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
% Note: RFA needles were not included in the UMB article.

%% Load data...
len_ang = length(v.vid1.outputs.CNR_tip);                                   % Nr. of angles studied per video.
len_ndl = length(ndl_sel);                                                  % Nr. of needles evaluated.
CNR_tip = cell(len_ang,len_ndl);
CNR_sha = cell(len_ang,len_ndl);

i_builder = 1; % Table builder index.
for index = 1:last_vid_nr
    fn = strcat('vid',num2str(index)); % Recreate fieldname.
    try                                                                     % If file data exists: acquire experimental conditions.
        for n = 1:9
            ECs2{i_builder,n} = v.(fn).inputs.ECs{n}; %#ok<SAGROW>
        end
        ECs2{i_builder,10} = v.(fn).inputs.angles;
        [~,pos] = ismember(ECs2{i_builder,1},ndl_sel);
        ECs2{i_builder,11} = pos;                                           % Link vid file needle type to ndl_sel index.
        
        % Output data: acquire contrast to noise ratios (CNR).
        if pos>0
            for i = 1:len_ang
                CNR_tip{i,pos} = [CNR_tip{i,pos}, ...
                    v.(fn).outputs.CNR_tip(i)];
                CNR_sha{i,pos} = [CNR_sha{i,pos}, ....
                    v.(fn).outputs.CNR_shaft(i)];
            end
        end
        
        % If file data exists: +1 to table builder index.
        i_builder = i_builder+1;
    catch
    end
end

%% Compute summary metrics.

% Medians and standard deviations.
CNR_sha_med = cellfun(@median,CNR_sha);
CNR_sha_std = cellfun(@std,CNR_sha);
CNR_tip_med = cellfun(@median,CNR_tip);
CNR_tip_std = cellfun(@std,CNR_tip);

% Median +/- std margins.
CNR_sha_plus = CNR_sha_med + CNR_sha_std;
CNR_sha_min = CNR_sha_med - CNR_sha_std;
CNR_tip_plus = CNR_tip_med + CNR_tip_std;
CNR_tip_min = CNR_tip_med - CNR_tip_std;

threshold = 0.5;
reps = 10;
angs = (1:32)'; % (25:5:180)';
posrm = ones(length(angs),reps).*angs;
tempmat_t = cellfun(@(col) vertcat(col{:}), num2cell(CNR_tip, 1),...
    'UniformOutput', false);
tempmat_s = cellfun(@(col) vertcat(col{:}), num2cell(CNR_sha, 1),...
    'UniformOutput', false);
for ib = 1:len_ndl
    for rep = 1:reps
        temps_t{ib,rep} = posrm(tempmat_t{ib}(:,rep)-threshold>0); %#ok<SAGROW>
        temps_s{ib,rep} = posrm(tempmat_s{ib}(:,rep)-threshold>0); %#ok<SAGROW>
        range_min_t(ib,rep) = min(temps_t{ib,rep});%#ok<SAGROW>
        range_max_t(ib,rep) = max(temps_t{ib,rep});%#ok<SAGROW>
        range_min_s(ib,rep) = min(temps_s{ib,rep});%#ok<SAGROW>
        range_max_s(ib,rep) = max(temps_s{ib,rep});%#ok<SAGROW>
    end
    range_t{ib} = round(median(range_min_t(ib,:),2)):...
        round(median(range_max_t(ib,:),2));%#ok<SAGROW>
%     rangs_sd_t(ib) = round(std(range_min_t(ib,:),2)):...
%         round(median(range_max_t(ib,:),2));%#ok<SAGROW>
    range_s{ib} = round(median(range_min_s(ib,:),2)):...
        round(median(range_max_s(ib,:),2));%#ok<SAGROW>

end

% Apply rotations, counterclockwise angular rotation.
rot_ang = pi*(180-v.(fn).inputs.angles)/180; 
for i2 = 1:len_ang
    rot_mat = [cos(rot_ang(i2)), sin(rot_ang(i2)); ...
        -sin(rot_ang(i2)), cos(rot_ang(i2))];
    t1 = rot_mat.*[1;0];
    x_fact(i2) = t1(1,1); %#ok<SAGROW>
    y_fact(i2) = t1(1,2); %#ok<SAGROW>
end
tip_med_x = CNR_tip_med.*x_fact'; 
tip_plus_x = CNR_tip_plus.*x_fact'; 
tip_min_x = CNR_tip_min.*x_fact'; 
sha_med_x = CNR_sha_med.*x_fact';
sha_plus_x = CNR_sha_plus.*x_fact';
sha_min_x = CNR_sha_min.*x_fact';

tip_med_y = CNR_tip_med.*y_fact';
tip_plus_y = CNR_tip_plus.*y_fact';
tip_min_y = CNR_tip_min.*y_fact';
sha_med_y = CNR_sha_med.*y_fact';
sha_plus_y = CNR_sha_plus.*y_fact';
sha_min_y = CNR_sha_min.*y_fact';

% Show data shafts.
patch_a = 0.4; % Alpha value (transparantie) of patches.
figure('units','normalized','outerposition',[0 0 1 1]), hold on,
max_v = 15; % Max. value on radial axis.
for sp = 1:subplots
    subplot(2,2,sp)
    title('Polar plot of needle shaft visibility versus insertion angle.')
    xlabel('Insertion angle [degrees]');
    ylabel('CNR (visibility, shaft) [-]');
    xlim([-(max_v+2),(max_v+2)]); ylim([0,(max_v+2)]);
    line(5*x_fact,5*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(10*x_fact,10*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(15*x_fact,15*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(max_v*x_fact,max_v*y_fact,'LineWidth',2,'Color','k',...
        'HandleVisibility','off');
    line(max_v*[x_fact(1),0,1],max_v*[y_fact(1),0,0],...
        'LineWidth',2,'Color','k','HandleVisibility','off');
    for i3 = 2:len_ang-1
        line(max_v*[0,x_fact(i3)],max_v*[0,y_fact(i3)],'LineStyle','-.',...
            'LineWidth',0.2,'Color',[.6 .6 .6],'HandleVisibility','off');
    end
    text(-15,6.5,'25'); text(-0.5,15.8,'90'); text(15.3,0.5,'180');
    for ndls = ShownPerSubplot{sp}
        patch([sha_plus_x(:,ndls);flipud(sha_min_x(:,ndls))],...
            [sha_plus_y(:,ndls);flipud(sha_min_y(:,ndls))],col_vec{ndls},...
            'FaceAlpha',patch_a);
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
    subplot(2,2,sp); 
    title('Polar plot of needle tip visibility versus insertion angle.')
    xlabel('Insertion angle [degrees]');
    ylabel('CNR (visibility, tip) [-]');
    xlim([-(max_v+2),(max_v+2)]); ylim([0,(max_v+2)]);
    line(5*x_fact,5*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(10*x_fact,10*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(15*x_fact,15*y_fact,'LineStyle','-.','Color','k',...
        'HandleVisibility','off');
    line(max_v*x_fact,max_v*y_fact,'LineWidth',2,'Color','k',...
        'HandleVisibility','off');
    line(max_v*[x_fact(1),0,1],max_v*[y_fact(1),0,0],...
        'LineWidth',2,'Color','k','HandleVisibility','off');
    for i3 = 2:len_ang-1
        line(max_v*[0,x_fact(i3)],max_v*[0,y_fact(i3)],'LineStyle','-.',...
            'LineWidth',0.2,'Color',[.6 .6 .6],'HandleVisibility','off');
    end
    text(-15,6.5,'25'); text(-0.5,15.8,'90'); text(15.3,0.5,'180');
    for ndls = ShownPerSubplot{sp}
        patch([tip_plus_x(:,ndls);flipud(tip_min_x(:,ndls))],...
            [tip_plus_y(:,ndls);flipud(tip_min_y(:,ndls))],col_vec{ndls},...
            'FaceAlpha',patch_a);
        line(tip_med_x(:,ndls),tip_med_y(:,ndls),'Color','k',...
            'HandleVisibility','off');
    end
    [~,h_legend] = legend(ndl_tags{ShownPerSubplot{sp}});
    PatchInLegend = findobj(h_legend, 'type', 'patch');
    for ptch_count = 1:length(ShownPerSubplot{sp})
        set(PatchInLegend(ptch_count), 'FaceAlpha', patch_a);
    end
end