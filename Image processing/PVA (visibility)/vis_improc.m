function vis_improc
%% MATLAB function for ultrasound frame selection and frame analysis.
% This MATLAB code is written as a part of a study on the quantification of 
% needle visibility and echogenicity in ultrasound images.
% Author: 	Nick J. van de Berg, Delft University of Technology.
% Date:     03-11-2017
% Contact:  N.J.P.vandeBerg@TUDelft.nl
% Website:  www.misit.nl/nick
% Journal:  Ultrasound in Medicine and Biology
% Title:    A methodical quantification of needle visibility and 
%           echogenicity in ultrasound images
% 
% **********         Instructions for data input.          **********
% [1] Make sure that the needle is in constant motion and that the video
%     does not have exessive 'idle'-time at the start or end. 
%
% [2] The filenames can contain metadata, which may be stored in a struct:
%     Used filename format: 'Needle type' repetition - timestamp.MP4 
%
% **********            Instructions for use.              **********
% The 'h' variable is a handles structure that is saved as UserData in 
% the constructed Graphical User Interface (GUI).
% 
% The GUI starts with a manual segmentation step. 
% [3] Find the needle in the two depicted images and place the blue 
%     <draggable> lines over them. 
% [4] Make the needle estimates as long as possible. 
% [5] Use one of the line end-points to estimate the needle tip position. 

% The current code assumes that the needle tip is always the line end-point 
% located closest to the center of the image (hence instruction [4]).

% Clicking <Ready> will resample the video by acquiring frames for a 
% specified series of insertion angles (h.angle_select).
% The <left> & <right> arrow keys enable skipping through the frames.
%
% **********    Mathematical clarifications & choices.     **********
% The used frames for the manual segmentation step are taken at 1/5th and 
% 4/5th of the total recording time. We purposely avoid the fully 
% orthogonal angles, as there may be large reverberation artefacts present.
%
% The manual needle segmentations is used to define (and rotate) a region 
% of interest (ROI) in the image. A search function subsequently defines 
% a linear needle fit and collects samples of the image foreground (FG) 
% and background (BG) to study the visibility of the needle tip and shaft 
% by means of a contrast-to-noise ratio (CNR).
% 
% Image FG samples have a fixed length (FG_tip=2 mm, FG_shaft=20 mm) and a 
% width that is equal to the needle diameter. The FG sample positions are
% found in a moving average search function. The BG sample has a length of 
% 40 mm, and a width equal to the max used needle diameter (2 mm).
%
% Be aware of the Matlab coordinate system conventions for '[x,y]':
% - imshow() & rectangle(): x+=right, y+=down, [1,1]=right top corner,
% - matrix notation: x+=down, y+=right, [1,1]=right top corner.
% Note: the rectangle() position after imshow() behaves differently from 
% its behaviour in a new figure, i.e. where x+=right, y+=up.

%% Start of the script & definition of variables.
clear; 

% Pixels per mm (approximated by means of imline length read-outs after
% placing them over the US image depth scale - from 0 to 15 cm deep):
h.pxmm = 2.85; % mean([2.85, 2.86, 2.85]).

% Needle 'insertion' angles under evaluation:  
h.angle_select = 25:5:180; % Frames out              <--------------------- Modify this line to retrieve frames for a different set of angles.
% Note: angles below 25 deg could typically not be reached due to physical 
% contact with the US probe.

% The FG/BG sample width is equal to the needle diameter, and the length is:
h.tip_l = round(2*h.pxmm); % Tip sample length [pxl].
h.sha_l = round(20*h.pxmm); % Shaft sample length [pxl].
h.bg_l = round(20*h.pxmm); % Shaft Background sample length [pxl].
h.bg_w = round(2*h.pxmm); % Background sample width [pxl]. 
h.fg_bg_o = round(2*h.pxmm); % Offset between FG and BG samples [pxl].
h.ndl_l = round(45*h.pxmm); % Total needle length under evaluation [pxl].

% Needle types used in this study:                   <--------------------- Definition of used needle types (as used during the experiments). 
h.unique_names = {'Bevel_22G', 'Trocar_18G', 'Steel_1mm', 'Steel_2mm',...
    'Niti_2mm', 'Steel_rough_2mm', 'Steel_1cut_2mm', 'Steel_2cut_2mm',...
    'Bevel_coat_22G', 'Trocar_coat_18G', 'RFA_2mm', 'RFA_coat_2mm'};
h.ndl_diam_mm = [0.7, 1.3, 1, 2, 2, 2, 2, 2, 0.7, 1.3, 2, 2]; % In [mm].
h.ndl_diam_px = round(h.ndl_diam_mm*h.pxmm); % Here: [2,4,3,6,6,6,6,6].
h.ndl_diam_px_default = h.bg_w; 
h.width = 50; % Margin around needle in the region of interest (ROI)[pxl].

% Start by selecting the video file (currently one at a time, although the
% code below is partly ready for multiselect - on the TO-DO list):
[filenames,~] = uigetfile('*.MP4','Select video file','multiselect','off');
if ~iscell(filenames) % In multiselect mode, a cell array is created.
    filenames = {filenames}; % Ensure constant var type.
    % Creates cell array in case only one file was selected.
end

% Preps for file loading loop:
vids = length(filenames); % Total number of files.
C = cell(vids,1); % Create cell array.
h.ECs = cell(vids,9); % Experimental conditions.
h.ECs_explain = {'Needle','Needle index','Repetition','Filename',... 
    'Frame rate','Video duration','Resolution','Number of frames','Time'};
h.vidin = cell(vids,1);

% File loading loop (partly rdy for 'multiselect'):  <--------------------- Construction of experimental conditions (EC) var: store file info / metadata.
for idx = 1:vids
    try % Get info from file names and store in EC struct.
        C{idx} = strsplit(filenames{idx});
        h.ECs{idx,1} = strrep(C{idx,1}(1), '''', ''); % Needle type.
        h.ECs{idx,2} = find(contains(h.unique_names,h.ECs{idx,1})); % Nr.
        rep = cell2mat(C{idx,1}(2));
        h.ECs{idx,3} = str2double(rep);
        if isempty(h.ECs{idx,2})
            h.ECs{idx,2} = 0; % Needle type not part of the specified list.
        end
        
        % Correction: some filenames were missing a space after rep number.
        if isnan(h.ECs{idx,2})
            h.ECs{idx,3} = str2double(rep(1:end-1));
        end
        
        % Needle diameter. 
        try h.ndl_d = h.ndl_diam_px(h.ECs{idx,2}); % Diameter of needle.
        catch
            % In case needle was not found/specified: default value.
            h.ndl_d = h.ndl_diam_px_default;
        end
        check_ECs = 1;
    catch % Bypass filename analysis: provide default inputs.
        h.ECs{idx,1} = 'Not found.';
        h.ECs{idx,2} = NaN;
        h.ECs{idx,3} = NaN;
        h.ndl_d = h.ndl_diam_px_default;
        check_ECs = 0;
    end
    
    % Video properties.
    video = VideoReader(filenames{idx}); %#ok<TNMLP>
    disp(strcat('Open for analysis:',filenames(idx)));
    h.ECs{idx,4} = filenames{idx};  % Video file name.
    h.ECs{idx,5} = video.FrameRate; % Framerate [fps].
    h.ECs{idx,6} = video.Duration; % Duration [s].
    h.ECs{idx,7} = [video.Width video.Height]; % Resolution.
    h.ECs{idx,8} = video.Duration*video.FrameRate; % Length [frames].
    if check_ECs
        h.ECs{idx,9} = C{idx,1}{4}(1:end-4); % Vid created time stamp.
    else
        h.ECs{idx,9} = NaN;
    end
    
    % Define two frames for video resampling: at ~360/5 = 72 degrees,
    % and 4*360/5 = 288 degrees.
    h.frame(1,1) = round(h.ECs{idx,8}/5);
    h.frame(1,2) = round(4*h.ECs{idx,8}/5);
    for i = 1:2 % Retrieve frames as intensity maps (gray-scale).
        h.frameselection(:,:,i) = rgb2gray(...
            read(video,h.frame(1,i))); %#ok<VIDREAD>
    end
    % Note: these angles are estimates, based on the video run time.
end
% To do [for multiselect]: video focus based on selection in a dropdown 
% menu or listbox, for easy switching between video files.
h.v_focus = 1; 


%% Create a GUI for further data processing and data storage.

% Create main figure. Size is based on the US frame resolution.
x2_gui = h.ECs{h.v_focus,7}(1);
y2_gui = h.ECs{h.v_focus,7}(2);
viewer = figure('Tag','viewer','Name',...
    strcat('Needle detection tool in ultrasound (',h.ECs{h.v_focus,4},').'),...
    'Color','white','Position',[10 10 2*x2_gui+30 y2_gui+50],'MenuBar',...
    'none','Toolbar','none','NumberTitle','off','Visible','on'); 

% Add widgets.
h.imshow_1 = axes('Units','Pixels','Visible','off','Position',...
    [10 40 x2_gui y2_gui]); axis equal
h.imshow_2 = axes('Units','Pixels','Visible','off','Position',...
    [x2_gui+20 40 x2_gui y2_gui]); axis equal
h.imshow_3 = axes('Units','Pixels','Visible','off','Position',...
    [x2_gui round(4.5*h.width) 8*h.width 2*h.width]); axis equal
h.readybutton = uicontrol(viewer,'Style','pushbutton','String','Ready',...
    'BackgroundColor','white','Units','normalized','position',...
    [0.47 0.01 0.06 0.04],'ForegroundColor','blue','Callback',@ready_CB);
h.backbutton = uicontrol(viewer,'Style','pushbutton','String','Back',...
    'BackgroundColor','white','Units','normalized','position',...
    [0.01 0.01 0.06 0.04],'ForegroundColor','blue','Callback',@back_CB);
h.texthelp = uicontrol(viewer,'Style','text','String','Processing frames.',...
    'position',[x2_gui+40 y2_gui-20 x2_gui-40 30],'FontSize',18,...
    'HorizontalAlignment', 'left','BackgroundColor','white',...
    'ForegroundColor','blue','Visible','off');
h.textangle = uicontrol(viewer,'Style','text','FontSize',18,'String',...
    'Angle [degrees]:15','BackgroundColor','white',...
    'HorizontalAlignment', 'left', 'position', [x2_gui+40 y2_gui-60 ...
    x2_gui-100 30],'ForegroundColor','blue','Visible','off');
h.textCNR_T = uicontrol(viewer,'Style','text','FontSize',18,'String',...
    'CNR Tip:','BackgroundColor','white','HorizontalAlignment', 'left', ...
    'position', [x2_gui+40 100 x2_gui-100 30], 'ForegroundColor','blue', ...
    'Visible','off');
h.textCNR_S = uicontrol(viewer,'Style','text','FontSize',18,'String',...
    'CNR Shaft:','HorizontalAlignment', 'left','BackgroundColor',...
    'white','position', [x2_gui+40 60 x2_gui-100 30], ...
    'ForegroundColor','blue','Visible','off');
h = reset(h);

% Store handles as user data.
set(viewer,'UserData',h);

% The back button (re)creates the starting frames and the draggable lines.
back_CB();


%% Callback functions (nested) for GUI interactions.

    % Reset axes.
    function h = reset(h)
        
        % Clear axes and turn off text visibility.
        x3_gui = h.ECs{h.v_focus,7}(1);
        y3_gui = h.ECs{h.v_focus,7}(2);
        cla(h.imshow_1);cla(h.imshow_2);cla(h.imshow_3);
        set(h.imshow_2,'Position',... % Back to the original size.
            [x3_gui+20 40 x3_gui y3_gui]);
        imshow(h.frameselection(:,:,1),'Parent',h.imshow_1); 
        imshow(h.frameselection(:,:,2),'Parent',h.imshow_2);
        set([h.texthelp,h.textangle,h.textCNR_T,h.textCNR_S,h.imshow_3],...
            'Visible', 'off');
        if isfield(h,'peak_x')
            fields = {'peak_x','peak_y'};
            h = rmfield(h,fields); % Remove tip search results.
        end
    end

    % Callback function 'Back' button.
    function h = back_CB(~,~)
        
        % Obtain user data main figure.
        h = get(viewer,'UserData');
        
        % Clear content from GUI axes.
        h = reset(h);
        
        % Check if video file has been previously opened and if draggable
        % lines have been set for this particular movie.
        filename = h.ECs{h.v_focus,4};
        counter = 0;
        if exist('vis_collected_data.mat','file')
            load vis_collected_data.mat v;
            fields = fieldnames(v);
            last_field = cell2mat(fields(end,1));                           % Requires sequential order of structure fields.
            last_vid_nr = str2double(last_field(4:end));
            for index = 1:last_vid_nr
                % Check if file name already exists in userdata.
                fieldname = strcat('vid',num2str(index));
                try
                    check = strcmp(filename,v.(fieldname).filename);
                    % When filename is found in .mat file.
                    if check == 1
                        % Create draggable lines & load other stored variables.
                        h.needle_est1 = imline(h.imshow_1,...
                            v.(fieldname).left_line);
                        h.needle_est2 = imline(h.imshow_2,...
                            v.(fieldname).right_line);
                        h.ang1 = v.(fieldname).left_line_angle;
                        h.ang2 = v.(fieldname).right_line_angle;
                        h.tip1 = v.(fieldname).left_tip;
                        h.tip2 = v.(fieldname).right_tip;
                    end
                    counter = counter + check;
                    
                catch
                end
            end
            % When mat-file exists, but this is a new video file (no strcmp match).
            if counter == 0 
                % Create draggable lines: default line positions and sizes.
                w = 200; d = 40; % Default sizes.
                h.needle_est1 = imline(h.imshow_1,[h.ECs{h.v_focus,7}(1)/2 ...
                    h.ECs{h.v_focus,7}(1)/2+w],[h.ECs{h.v_focus,7}(2)/2 ...
                    h.ECs{h.v_focus,7}(2)/2-d]);
                h.needle_est2 = imline(h.imshow_2,[h.ECs{h.v_focus,7}(1)/2 ...
                    h.ECs{h.v_focus,7}(1)/2-w],[h.ECs{h.v_focus,7}(2)/2 ...
                    h.ECs{h.v_focus,7}(2)/2-d]);
                h.ang1 = 90 - 180*atan(d/w)/pi;
                h.ang2 = 270 + 180*atan(d/w)/pi;
                h.tip1 = h.ECs{h.v_focus,7}/2;
                h.tip2 = h.ECs{h.v_focus,7}/2;
            end
        % When userdata does not yet exist.
        else 
            % Create draggable lines: default line positions and sizes.
            w = 200; d = 40; % Default sizes.
            h.needle_est1 = imline(h.imshow_1,[h.ECs{h.v_focus,7}(1)/2 ...
                h.ECs{h.v_focus,7}(1)/2+w],[h.ECs{h.v_focus,7}(2)/2 ...
                h.ECs{h.v_focus,7}(2)/2-d]);
            h.needle_est2 = imline(h.imshow_2,[h.ECs{h.v_focus,7}(1)/2 ...
                h.ECs{h.v_focus,7}(1)/2-w],[h.ECs{h.v_focus,7}(2)/2 ...
                h.ECs{h.v_focus,7}(2)/2-d]);
            h.ang1 = 90 - 180*atan(d/w)/pi;
            h.ang2 = 270 + 180*atan(d/w)/pi;
            h.tip1 = h.ECs{h.v_focus,7}/2;
            h.tip2 = h.ECs{h.v_focus,7}/2;
        end
        
        % Add callbacks and line tracking objects.
        % To do: reduce to single callback function.
        addNewPositionCallback(h.needle_est1,@needle_est1_CB);
        addNewPositionCallback(h.needle_est2,@needle_est2_CB);
        h.api_t1 = iptgetapi(h.needle_est1);
        h.api_t2 = iptgetapi(h.needle_est2);
        fcn_t1 = makeConstrainToRectFcn('imline',...
            [0 h.ECs{h.v_focus,7}(1)],[0 h.ECs{h.v_focus,7}(2)]);
        h.api_t1.setPositionConstraintFcn(fcn_t1);
        h.api_t2.setPositionConstraintFcn(fcn_t1);
        
        % Set buttons.
        set(h.readybutton,'Enable','on');
        set(h.backbutton,'Enable','off');
        
        % Update user data.
        set(viewer,'UserData',h);

    end

    % Callback draggable line left axes.
    function h = needle_est1_CB(pos)

        % Obtain user data main figure.
        h = get(viewer,'UserData');
        pause(0.025) % To reduce update rate during imline movement.
        
        % Needle insertion angle computation.
        dx = pos(2)-pos(1);
        dy = pos(3)-pos(4); % Note that [0,0] is left top corner...
        ang_rad = atan(dy/dx);
        h.ang1 = 90 - 180*ang_rad/pi; % Angle with vertical line [degrees].
        h.line_length = sqrt(dx^2+dy^2);
        
        % Distance to frame center.
        dist_xy = pos - h.ECs{h.v_focus,7}/2;
        dist_pyth = sqrt(dist_xy(:,1).^2+dist_xy(:,2).^2);
        [~,index_nearest] = min(dist_pyth); %        <--------------------- Tip is defined as the imline end-point nearest to center of frame.
        h.tip1 = pos(index_nearest,:);
        
        % Update user data.
        set(viewer,'UserData',h);

    end

    % Callback draggable line right axes.
    function h = needle_est2_CB(pos)

        % Obtain user data main figure.
        h = get(viewer,'UserData');
        pause(0.025) % To reduce update rate during imline movement.
        
        % Needle insertion angle computation.
        dx = pos(1)-pos(2);
        dy = pos(3)-pos(4); % Note that [0,0] is left top corner...
        ang_rad = atan(dy/dx);
        h.ang2 = 270 + 180*ang_rad/pi; % Angle with vertical line [degrees].
        
        % Distance to frame center.
        dist_xy = pos - h.ECs{h.v_focus,7}/2;
        dist_pyth = sqrt(dist_xy(:,1).^2+dist_xy(:,2).^2);
        [~,index_nearest] = min(dist_pyth); %        <--------------------- Tip is defined as the imline end-point nearest to center of frame.
        h.tip2 = pos(index_nearest,:);

        % Update user data.
        set(viewer,'UserData',h);

    end

    % Callback 'Ready' button. Note that clicking this button will
    % overwrite the stored positions of the draggable line objects!!!
    function h = ready_CB(~,~)

        % Obtain user data main figure.
        h = get(viewer,'UserData');
        
        % ======== PART I: Check previous stored user data. ========
        % Store manually segmented needle positions.
        pos1 = h.api_t1.getPosition();
        pos2 = h.api_t2.getPosition();
        filename = h.ECs{h.v_focus,4};
        counter = 0;
        if ~exist('vis_collected_data.mat','file')
            v.info = ...
                'Storage of user inputs for the needle visibility study.';
            v.vid1 = struct('filename',filename,'left_line',pos1,...
                'right_line',pos2,'left_line_angle',h.ang1,...
                'right_line_angle',h.ang2,'left_tip',h.tip1,...
                'right_tip',h.tip2);
            save vis_collected_data.mat v;
        else
            load vis_collected_data.mat v;
            fields = fieldnames(v);
            last_field = cell2mat(fields(end,1));                           % Requires sequential order of structure fields.
            last_vid_nr = str2double(last_field(4:end));
            for index = 1:last_vid_nr
                % Check if file name already exists in userdata.
                fieldname = strcat('vid',num2str(index));
                try
                    check = strcmp(filename,v.(fieldname).filename);
                
                    % When filename is found in .mat file.
                    if check == 1
                        v.(fieldname).left_line = pos1;
                        v.(fieldname).right_line = pos2;
                        v.(fieldname).left_line_angle = h.ang1;
                        v.(fieldname).right_line_angle = h.ang2;
                        v.(fieldname).left_tip = h.tip1;
                        v.(fieldname).right_tip = h.tip2;
                        save vis_collected_data.mat v;
                    end
                    counter = counter + check;
                catch
                end
            end
            if counter == 0 % m-file exists, but no str match (new video).
                newvid = strcat('vid',num2str(len+1));
                v.(newvid).filename = filename;
                v.(newvid).left_line = pos1; 
                v.(newvid).right_line = pos2;
                v.(newvid).left_line_angle = h.ang1;
                v.(newvid).right_line_angle = h.ang2; 
                v.(newvid).left_tip = h.tip1; 
                v.(newvid).right_tip = h.tip2;
                save vis_collected_data.mat v;
            end
        end
        
        % ======== PART II: Collect frames from video. ========
        % Process the manual segmentation step.
        % Determine frames for further analysis. %   <--------------------- Relation between: desired angles -> frame numbers.
        angular_range = h.ang2 - h.ang1;
        frame_range = h.frame(1,2) - h.frame(1,1);
        h.frames_per_degree = frame_range / angular_range;
        delta_ang = h.angle_select - h.ang1;
        delta_frames = delta_ang*h.frames_per_degree;
        h.frames_out = round(h.frame(1,1) + delta_frames);
        
        % Proceed with left axis only, make assistive text visible.
        dummy_image = ones(600,10);
        imshow(dummy_image, 'Parent', h.imshow_2);
        imshow(dummy_image, 'Parent', h.imshow_3);
        set([h.texthelp,h.textangle,h.textCNR_T,h.textCNR_S,h.imshow_3],...
            'Visible', 'on');
        
        % Retrieving frames and show first frame in left axes.
        for ii = 1:length(h.frames_out)
            h.imagedata(:,:,ii) = rgb2gray(read(video,h.frames_out(ii)));
        end
        h.frame_index = 1;
        imshow(h.imagedata(:,:,h.frame_index), 'Parent', h.imshow_1);
        
        % ======== PART III: Analyse frames. ========
        % Functions for definiting and analysing the frames.
        h = prepare_frames(h); 
        for scan_frame = 1:length(h.frames_out) %    <--------------------- Loop through series of frame processing functions.
            h = best_fit_fun(h,scan_frame);
            h = analyse_ROI(h,scan_frame);
            h = compute_CNR(h,scan_frame);
        end
        h = update_axes(h);
         
        % Add new callback function for skipping through images.
        set(viewer, 'KeyPressFcn', @frame_skip)
        
        % Set buttons and update user data.
        set(h.texthelp,'String',...
            'Skip through frames with < and > arrow buttons.');
        set(h.readybutton,'Enable','off');
        set(h.backbutton,'Enable','on');
        set(viewer,'UserData',h);

    end 
        
    % Callback left and right arrow buttons to skip through frames.
    function h = frame_skip(~,event)
        
        % Obtain user data main figure.
        h = get(viewer,'UserData');

        % Only responds to 2 keyboard buttons..
        if strcmp(event.Key, 'leftarrow') 
            if h.frame_index > 1
                h.frame_index = h.frame_index - 1;
            else
                h.frame_index = length(h.frames_out); 
            end
                        
            % Update frame.
            h = update_axes(h);
        elseif strcmp(event.Key, 'rightarrow')
            if h.frame_index < length(h.frames_out)
                h.frame_index = h.frame_index + 1;
            else
                h.frame_index = 1; 
            end
                        
            % Update frame.
            h = update_axes(h);
        end

        % Update user data.
        set(viewer,'UserData',h);

    end

    % Visual processing of the frame skips in the GUI.
    function h = update_axes(h)
        
        % Left axes:
        % Show current frame and needle estimate from manual segmentation.
        imshow(h.imagedata(:,:,h.frame_index), 'Parent', h.imshow_1);
        ang_txt = num2str(h.angle_select(h.frame_index)); % GUI text.
        set(h.textangle, 'String', strcat('Angle [degrees]: ', ang_txt));
        h.xax = line([0 h.ECs{h.v_focus,7}(1)], [h.origin_gcs(2) ... 
            h.origin_gcs(2)],'Parent',h.imshow_1,'Color','white'); % Show gcs.
        h.yax = line([h.origin_gcs(1),h.origin_gcs(1)],[0 ...
            h.ECs{h.v_focus,7}(2)],'Parent',h.imshow_1,'Color','white');
        h.needle_est = line([h.ndl_t_est(1,h.frame_index),... 
            h.ndl_d_est(1,h.frame_index)], [h.ndl_t_est(2,h.frame_index),...
            h.ndl_d_est(2,h.frame_index)],'Parent',h.imshow_1,'Color','b',...
            'LineStyle','--');        

        % Right top axes:
        % Show filtered ROI, tip estimate and fit line.
        fit_name = strcat('fit',num2str(h.frame_index));
        imshow(h.ROI_f(:,:,h.frame_index), 'Parent', h.imshow_2);
        h.needle_line = line([1 4*h.width],[h.(fit_name).cfit(1),...
            h.(fit_name).cfit(1)],'Color','r','LineStyle','-',...
            'parent',h.imshow_2); % y-data 0th order fit, hori line.
        h.needle_tip = line(h.peak_x(h.frame_index),h.peak_y(h.frame_index),...
            'parent',h.imshow_2,'Color','b','LineStyle','none','Marker','o');

        % Right bottom axes:
        % Show original ROI with (FG & BG) image sample boxes.
        imshow(h.ROI(:,:,h.frame_index), 'Parent', h.imshow_3);
        h.FG_tip_r = rectangle('Position',h.(fit_name).fg_t,...
            'EdgeColor','b','parent',h.imshow_3);
        h.FG_sha_r = rectangle('Position',h.(fit_name).fg_s,...
            'EdgeColor','b','parent',h.imshow_3);
        h.BG_tip_r = rectangle('Position',h.(fit_name).bg_t,...
            'EdgeColor','r','parent',h.imshow_3);
        h.BG_sha_r = rectangle('Position',h.(fit_name).bg_s,...
            'EdgeColor','r','parent',h.imshow_3);
        % To do (for visual inspection only): Replace rectangle() by lines
        % that can follow a higher order needle fit.
        
        % Update text fields.
        round_CNR_tip = num2str(round(100*h.(fit_name).CNR_tip)/100);
        round_CNR_sha = num2str(round(100*h.(fit_name).CNR_sha)/100);
        set(h.textCNR_T,'string',strcat('CNR Tip:',round_CNR_tip)); 
        set(h.textCNR_S,'string',strcat('CNR Shaft:',round_CNR_sha)); 
        
        % % Check centroids of connected components near needle estimate.
        % name_S = strcat('Centroids',num2str(h.frame_index));
        % line(h.C.(name_S)(:,1),h.C.(name_S)(:,2),'LineStyle','none',...
        %     'Marker','*','parent',h.imshow_2);

        % Write results to workspace:
        inputs.ECs = h.ECs;
        inputs.ECs_explain = h.ECs_explain;    
        inputs.angles = h.angle_select;
        samples.fgt = h.FGT;
        samples.fgs = h.FGS;
        samples.bg = h.BG;
        for fr = 1:length(h.angle_select)
            fit_name2 = strcat('fit',num2str(fr));
            results.CNR_cfit(:,fr) = h.(fit_name2).cfit';
            results.CNR_tip(fr) = h.(fit_name2).CNR_tip;
            results.CNR_shaft(fr) = h.(fit_name2).CNR_sha;
        end
        assignin('base','ECs',inputs)
        assignin('base','CNRs',results);
        assignin('base','ROIs',{h.ROI,h.ROI_f,h.maxima});
        assignin('base','SMPLs',samples);
        
        % Write results to userdata mat file:
        filename = cell2mat(h.ECs(h.v_focus,4));
        load vis_collected_data.mat v;
        fields = fieldnames(v);
        last_field = cell2mat(fields(end,1));                               % Requires sequential order of structure fields.
        last_vid_nr = str2double(last_field(4:end));
        for index = 1:last_vid_nr
            % Search for filename in userdata.
            fieldname = strcat('vid',num2str(index));
            try
                check = strcmp(filename,v.(fieldname).filename);
                % When filename is found in .mat file.
                if check == 1
                    v.(fieldname).inputs = inputs;
                    v.(fieldname).outputs = results;
                    save vis_collected_data.mat v;
                end
            catch
            end
        end        
    end


    %% Image processing functions (nested).
    
    % Outputs are the regions of interest (ROIs), rotated so that the needle 
    % estimate in each ROI has the same horizontal orientation. These ROIs
    % are later used in an automated needle search algorithm.
    function h = prepare_frames(h)
        
        % The mean location of the two manually segmented needle tips is 
        % the point of rotation (and origin) of the global coord system (gcs).
        h.origin_gcs = mean([h.tip1; h.tip2]);
        ndl_tip_gcs = h.tip1 - h.origin_gcs; % Derived from user input.

        % A local coordinate system (lcs) follows the tip position and
        % needle orientation in the gcs. During rotation, the offset
        % between the lcs and gcs is assumed to remain constant!
        theta = pi*h.ang1/180; 
        ndl_tip_lcs = [cos(theta) sin(theta); -sin(theta) cos(theta)]*... 
            ndl_tip_gcs'; %                          <--------------------- Definition of rotation matrix.
        
        % This allows for tip estimations of intermediate angles by means 
        % of angular interpolation.
        counter = 1;
        h.ndl_t_est = NaN(2,length(h.angle_select)); % Tip estimate.
        h.ndl_d_est = NaN(2, length(h.angle_select)); % Distal loc on needle.
        for theta = pi*h.angle_select/180 
            
            % Rotation matrix: reverse direction -> sin / -sin swapped.
            rot_matrix = [cos(theta) -sin(theta); sin(theta) cos(theta)]; 
            h.ndl_t_est(:,counter) = rot_matrix*ndl_tip_lcs + h.origin_gcs'; 
            h.ndl_d_est(:,counter) = rot_matrix*(ndl_tip_lcs + [0 -200]') +...
                h.origin_gcs'; % Needle length = 200 (for visual inspection).
            
            % The imrotate function rotates around the image center. By
            % padding the original image it is possible to align this point
            % of rotation with the ndl_tip. The width of the padding should 
            % be equal to 2*ndl_tip_lcs.
            padding = 2*(h.ECs{h.v_focus,7}/2-round(h.ndl_t_est(:,counter))');
            
            % Create dummy images with the padded image size.
            % Note: the frame size will now start to vary..
            h.image_padded{counter} = zeros(h.ECs{h.v_focus,7}(2)+...
                abs(padding(2)),h.ECs{h.v_focus,7}(1)+abs(padding(1)),'uint8');
            
            % Superimpose image (make sure padding is on the correct side).
            if padding(1) > 0
                x_offset = padding(1)+1;
            else
                x_offset = 1;
            end
            if padding(2) > 0
                y_offset = padding(2)+1;
            else
                y_offset = 1;
            end
            h.image_padded{counter}(y_offset:y_offset+h.ECs{h.v_focus,7}(2)-1,...
                x_offset:x_offset+h.ECs{h.v_focus,7}(1)-1) = ...
                h.imagedata(:,:,counter);
            
            % Rotate around padded-image center.
            h.imagedata_rot{counter} = imrotate(h.image_padded{counter},...
                270+h.angle_select(counter));
            h.image_center(:,counter) = round(size(h.imagedata_rot{counter})/2)';
            
            % Determine ROI (box around needle with a fixed size), note:
            % h.width was defined in the script init section.
            h.ROI(:,:,counter) = h.imagedata_rot{counter}...
                (h.image_center(1,counter)-h.width:...
                h.image_center(1,counter)+h.width,...
                h.image_center(2,counter)-h.width:... % 1x left.
                h.image_center(2,counter)+3*h.width); % 3x right (4x total).
            
            % Update counter.
            counter = counter + 1;
        end        
    end

    % Outputs are the filtered ROI and a linear needle fit (cfit). 
    function h = best_fit_fun(h,scan_frame) 
        
        % Scan region of interest for each of the selected frames.
        fit_name = strcat('fit',num2str(scan_frame));
        ROI = h.ROI(:,:,scan_frame);
        rows = size(ROI,1);
        cols = size(ROI,2);
        h.range = 1:rows;
        
        % Location-based augmentation function: increasing the relative
        % brightness of pixels close to the previous needle estimate. 
        ROI2 = ROI; % Reference to original. 
        if scan_frame == 1 % For 1st frame, use manual segmentation inputs.
            y_est = h.width;
        else % Use prev frame outputs.
            y_est = h.peak_y(scan_frame-1);
        end
        
        % The ROI should contain the needle in all of the frames. A further
        % narrowing of the search box per frame will help to deal with img
        % artefacts (such as reverberations) and other distracting features
        % per ROI. This is done by assuming a max. allowable needle displ 
        % with respect to the previous position estimate [x_est,y_est]. 
        dev = h.ndl_diam_px_default;
        row_cuts = y_est+[-dev,dev];
        ROI2(1:row_cuts(1),:) = zeros(row_cuts(1),cols);
        ROI2(row_cuts(2):end,:) = zeros(rows-row_cuts(2)+1,cols);

        % Quadratic function with y_max=1. Peak at [x_est,y_est].
        a1 = dev;                            %       <--------------------- Filter: location-based image augmentation. 
        a2 = h.width;
        b1 = y_est-dev;
        b2 = 0;
        h.aug_rows(scan_frame,:)=-((h.range-b1)/a1).^2+2*(h.range-b1)/a1;
        h.aug_cols(scan_frame,:)=-((h.range-b2)/a2).^2+2*(h.range-b2)/a2;
        for d_i = row_cuts(1):row_cuts(2)
           ROI2(d_i,:) = ROI2(d_i,:)*h.aug_rows(scan_frame,d_i);
        end
        for d_ii = 1:h.width
           ROI2(:,d_ii) = ROI2(:,d_ii)*h.aug_cols(scan_frame,d_ii);
        end
        % Note I: a different degree of BG noise (tissue inhomogeneity) may 
        % benefit from a stricter or less strict function. 
        % Note II: in case the function goes below zero, uint8 values are 
        % automatically clipped at zero (black pixels).
        % Note III: offset b1 could be based on the fit for scan_frame > 1, 
        % i.e. a seperate offset per column (for higher order fits).
                        
        % Store to display.
        h.ROI_f(:,:,scan_frame) = uint8(ROI2); % Filtered image.
        ROI2_ind = reshape(ROI2,[1 rows*cols]); % Data vector for search.

        % Make a fit to the remaining coordinates in ROI_f. The n highest
        % peaks in the filtered data are used for this. Polynomial needle 
        % fits of n'th order can be derived, using the coefficients vector 
        % 'cfit'. The current analysis uses a basic (0th order) horizontal 
        % line: Y = p1 (no ndl_x dependency).
        n = 50; 
        [pks,pl_f]=findpeaks(double(ROI2_ind),'SortStr','descend',...
            'MinPeakDistance',round(rows/2),'NPeaks',n);
        [ROI_y_data, ROI_x_data] = ind2sub(size(ROI),pl_f); 
        h.maxima(:,:,scan_frame) = [ROI_x_data;ROI_y_data;pks];
        h.(fit_name).cfit = round(median(ROI_y_data)); % Poly coefficients.
        h.(fit_name).line = polyval(h.(fit_name).cfit,1:4*h.width);
        % Note I: The second ind2sub output can provide ROI_x_data.
        % Note II: cfit_const determines the order of the fit. A higher 
        % order fit can be obtained by (for example):
        % h.(fit_name).cfit = polyfit(x, y, 1); % Input #3 = order. 
    end

    % Outputs are the tip coordinate, obtained in [local_tip_search()], and 
    % a cfit line evaluation to find coordinates for the CNR computations.
    function h = analyse_ROI(h,scan_frame)
                        
        % Update right axis size: data=4*width, axis=8*width (2x magnified).
        set(h.imshow_2, 'Position', ...
            [round(h.ECs{h.v_focus,7}(1)) 7*h.width 8*h.width 2*h.width]); 
        
        % Check brightness along ndl line and find h.peak_x
        [h] = local_tip_search(h,scan_frame);

        % Use fit for a needle tip search & the shaft offset [x,y]-coords.
        % The slope may be used for first order polynomial needle fits. 
        fit_name = strcat('fit',num2str(scan_frame));
        h.peak_y(scan_frame) = round(polyval(h.(fit_name).cfit, ...
            h.peak_x(scan_frame)));
        h.(fit_name).tip = [h.peak_x(scan_frame) h.peak_y(scan_frame)]; 
        h.(fit_name).slope = atan((h.(fit_name).line(end)-... % Slope.
            h.(fit_name).line(1))/length(h.(fit_name).line));
                
        % Rectangular coordinates FG_tip box.
        h.(fit_name).FG_t_x0 = h.peak_x(scan_frame);
        h.(fit_name).FG_t_dx = round(h.tip_l*cos(h.(fit_name).slope));
        h.(fit_name).FG_t_y0 = h.peak_y(scan_frame) - floor(0.5*h.ndl_d);
        h.(fit_name).FG_t_dy = h.ndl_d;    
        
        % Find the optimal location for the FG_shaft sample. Evaluate the
        % remaining needle length (right of the FG_tip sample). 
        window = round(h.sha_l*cos(h.(fit_name).slope));
        s0 = h.(fit_name).FG_t_x0 + h.(fit_name).FG_t_dx;
        if s0 + h.ndl_l < size(h.ndl_line_vals,2)
            s1 = s0 + h.ndl_l;
        else
            s1 = size(h.ndl_line_vals,2);
        end
        array_in = h.ndl_line_vals(:,s0:s1);
        FG_sha_opt = mov_avg_f(array_in, window); % Search optimum.
        % Note: search runs from just behind the tip up to h.ndl_l from
        % this point. This excludes the last section of the ROI, as it may
        % contain (parts of) the needle clamp. 
        
        % Rectangular coordinates FG_shaft box.
        h.(fit_name).FG_s_x0 = FG_sha_opt + h.(fit_name).FG_t_x0 + ...
            h.(fit_name).FG_t_dx;
        h.(fit_name).FG_s_dx = window;
        h.(fit_name).FG_s_y0 = round(polyval(h.(fit_name).cfit, ...
            h.(fit_name).FG_s_x0)) - floor(0.5*h.ndl_d);
        h.(fit_name).FG_s_dy = h.ndl_d;
        
        % Rectangular coordinates BG_tip box.
        h.(fit_name).BG_t_x0 = h.peak_x(scan_frame);
        h.(fit_name).BG_t_dx = round(h.tip_l*cos(h.(fit_name).slope));
        h.(fit_name).BG_t_y0 = h.peak_y(scan_frame) - floor(0.5*h.ndl_d) - ...
            h.bg_w - h.fg_bg_o + 1;
        h.(fit_name).BG_t_dy = h.bg_w; 
        
        % Rectangular coordinates BG_shaft box.
        h.(fit_name).BG_s_x0 = h.(fit_name).FG_s_x0;
        h.(fit_name).BG_s_dx = round(h.bg_l*cos(h.(fit_name).slope));
        h.(fit_name).BG_s_y0 = round(polyval(h.(fit_name).cfit, ...
            h.(fit_name).BG_s_x0)) - floor(0.5*h.ndl_d) - ...
            h.bg_w - h.fg_bg_o + 1;
        h.(fit_name).BG_s_dy = h.bg_w;
    end
    % Note: all ROI samples are visualized as rectangles, whereas CNR data 
    % is obtained with a polyval (depiction only correct for 0th order).  

    % Output is an estimated x-coordinate for the needle tip.
    function h = local_tip_search(h,scan_frame)
        
        % Retrieve brightness values array along needle fit. 
        % Penalty function: slope from y([0:end])=[1:0] to favour search 
        % results on the left (needle points to this direction).
        ROI = h.ROI_f(:,:,scan_frame);
        fit_name = strcat('fit',num2str(scan_frame));
        ndl_line_y = h.(fit_name).line;
        ndl_len_y = length(ndl_line_y);
        h.ndl_line_vals = zeros(h.ndl_d,ndl_len_y); 
        penalty = [fliplr(h.range)/max(h.range) ... 
            zeros(1,ndl_len_y-length(h.range))];
        for ndl_x = 1:ndl_len_y
            y0 = ndl_line_y(ndl_x) - floor(0.5*(h.ndl_d-1));
            h.ndl_line_vals(:,ndl_x) = ROI(y0:(y0+h.ndl_d-1), ndl_x);
        end
        ndl_line_vals_p = h.ndl_line_vals.*penalty;
        
        % The tip is considered to be the brightest (penalized) area. Some 
        % tips are nonechogenic. In case this search gives no result close 
        % to the estimated location, assume the tip has stayed in place. 
        window = h.tip_l; % Max. allowable deviation of tip position [pxl].
        if scan_frame == 1
            x_range = 1:size(ndl_line_vals_p,2);
            x_offset = 0;
        elseif scan_frame < 4
            x_range = min(h.peak_x)-2*window:max(h.peak_x)+2*window;
            x_range = x_range(x_range>0); % Array indices always > 0.
            x_offset = x_range(1)-1;
        else
            temp_peak_x = h.peak_x(end-2:end);
            x_range = min(temp_peak_x)-2*window:max(temp_peak_x)+2*window;
            x_range = x_range(x_range>0); % Array indices always > 0.
            x_offset = x_range(1)-1;
        end
        x_res = mov_avg_f(ndl_line_vals_p(:,x_range), window); 
        h.peak_x(scan_frame) = x_res + x_offset;
        if h.peak_x(scan_frame)<1 % Mind that this answer can be wrong!
            % disp([scan_frame,h.peak_x(scan_frame)]);
            h.peak_x(scan_frame) = 1;
        end
    end
    
    % Find the window location that results in the highest average pixel
    % intensity using a moving average filter. The inputs are a vector
    % that needs to be analysed and the window size. The output is the
    % first coordinate of the window with the highest moving avg value.
    function max_idx = mov_avg_f(array_in, window)
        max_mean = 0;
        max_idx = 1; % Default output.
        running_idx = 0;
        for idx_0 = 1:(length(array_in)-window)
            running_idx = running_idx+1;
            running_mean = mean(mean(array_in(:,idx_0:(idx_0+window-1))));
            if running_mean > max_mean
                max_mean = running_mean;
                max_idx = running_idx;
            end
        end
    end

    % Determine the foreground (FG) and background (BG) image samples and
    % calculate the contrast-to-noise-ratio (CNR). In this computation, the
    % contrast (C) is denoted as the img intensity difference between the 
    % FG and BG, whereas the noise (N) is the std in the BG sample.
    function h = compute_CNR(h,scan_frame)
        
        % Use the original image.
        ROI = h.ROI(:,:,scan_frame);
        
        % Positions of img objects [rectangle()] depicting the samples. 
        fit_name = strcat('fit',num2str(scan_frame));
        h.(fit_name).fg_t = [h.(fit_name).FG_t_x0, h.(fit_name).FG_t_y0,...
            h.(fit_name).FG_t_dx, h.(fit_name).FG_t_dy]; 
        h.(fit_name).fg_s = [h.(fit_name).FG_s_x0, h.(fit_name).FG_s_y0,...
            h.(fit_name).FG_s_dx, h.(fit_name).FG_s_dy];
        h.(fit_name).bg_t = [h.(fit_name).BG_t_x0, h.(fit_name).BG_t_y0,...
            h.(fit_name).BG_t_dx, h.(fit_name).BG_t_dy];
        h.(fit_name).bg_s = [h.(fit_name).BG_s_x0, h.(fit_name).BG_s_y0,...
            h.(fit_name).BG_s_dx, h.(fit_name).BG_s_dy];
        
        % Get the image intensity data of the FG tip sample. 
        c1 = 1;
        x1 = h.(fit_name).FG_t_x0;
        dx1 = h.(fit_name).FG_t_dx;
        FG_tip = nan(h.ndl_d,dx1);
        for col1 = x1:(x1+dx1-1)
            y1 = h.(fit_name).line(col1) - floor(0.5*h.ndl_d-1); 
            FG_tip(:,c1) = ROI(y1:(y1+h.ndl_d-1), col1);
            c1 = c1+1;
        end
        
        % Get the image intensity data of the FG shaft sample.
        c2 = 1;
        x2 = h.(fit_name).FG_s_x0-1;
        dx2 = h.(fit_name).FG_s_dx;
        FG_sha = nan(h.ndl_d,dx2);
        for col2 = x2:(x2+dx2-1)
            y2 = h.(fit_name).line(col2) - floor(0.5*h.ndl_d-1); 
            FG_sha(:,c2) = ROI(y2:(y2+h.ndl_d-1), col2);
            c2 = c2+1;
        end

        % Get the image intensity data of the BG tip sample. 
        c3 = 1;
        x3 = h.(fit_name).BG_t_x0;
        dx3 = h.(fit_name).BG_t_dx;
        BG_tip = nan(h.bg_w,dx3);
        for col3 = x3:(x3+dx3-1)
            y3 = h.(fit_name).line(col3) - floor(0.5*(h.ndl_d-1)) - ...
                h.bg_w - h.fg_bg_o; 
            BG_tip(:,c3) = ROI(y3:(y3+h.bg_w-1), col3);
            c3 = c3+1;
        end
        
        % Get the image intensity data of the BG shaft sample.
        c4 = 1;
        x4 = h.(fit_name).BG_s_x0-1;
        dx4 = h.(fit_name).BG_s_dx;
        BG_sha = nan(h.bg_w,dx4);
        for col4 = x4:(x4+dx4-1)
            y4 = h.(fit_name).line(col4) - floor(0.5*(h.ndl_d-1)) - ...
                h.bg_w - h.fg_bg_o;
            BG_sha(:,c4) = ROI(y4:(y4+h.bg_w-1), col4);
            c4 = c4+1;
        end

        % The BG sample is composed of BG_tip and BG_sha.
        BG = horzcat(BG_tip,BG_sha);
        
        % Store for workspace.
        h.FGT{scan_frame} = FG_tip;
        h.FGS{scan_frame} = FG_sha;
        h.BG{scan_frame} = BG;
        
        % Reshape matrix to array and get the means and stds: 
        FG_tip = double(FG_tip); FG_sha = double(FG_sha); BG = double(BG);
        FG_tip_m = mean(reshape(FG_tip,[1,size(FG_tip,1)*size(FG_tip,2)]));
        FG_sha_m = mean(reshape(FG_sha,[1,size(FG_sha,1)*size(FG_sha,2)]));
        BG_tot_m = mean(reshape(BG,[1,size(BG,1)*size(BG,2)]));
        BG_tot_s = std(reshape(BG,[1,size(BG,1)*size(BG,2)]));
        % Note: std() did not like uint8 var type inputs.
        
        % Contrast to noise ratio: %                 <--------------------- Definition of CNR values, computed for the needle tip and shaft.
        h.(fit_name).CNR_tip = abs(FG_tip_m-BG_tot_m)/BG_tot_s; 
        h.(fit_name).CNR_sha = abs(FG_sha_m-BG_tot_m)/BG_tot_s;       
    end

end
