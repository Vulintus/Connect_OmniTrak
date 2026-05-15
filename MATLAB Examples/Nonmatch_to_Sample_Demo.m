function Nonmatch_to_Sample_Demo

% 
% Nonmatch_to_Sample_Demo.m
%
%   copyright 2026, Vulintus, Inc.
%
%   This demo shows a minimal implementation of a visual Delayed Non-Match
%   to Sample task using two OmniTrak nosepokes/pellet receivers connected
%   to the OmniTrak Controller.
%   
%   UPDATE LOG:
%   2026-05-15 - Drew Sloan - Function first created.
%                            

%% Set these task parameters up front.
inter_trial_interval = 30;                                                  %Time between trials in seconds.
cue_duration = 3.0;                                                         %Duration of the light cue, in seconds.
cue_colors = [0, 1, 0; 0, 0, 1];                                            %Two light cue colors for testing non-matching.
response_delay = [1,10];                                                    %Bounds of a randomized response delay, in seconds.
response_window = 5;                                                        %Length of time the subject has to choose a nosepoke, in seconds.
trial_start_tone_freq = 2000;                                               %Trial start tone frequency, in Hz.
trial_start_tone_dur = 100;                                                 %Trial start tone duration, in milliseconds.
response_start_tone_freq = 3000;                                            %Response window start tone frequency, in Hz.
response_start_tone_dur = 100;                                              %Response window start tone duration, in milliseconds.
wrong_choice_tone_freq = 100;                                               %"Punishment" tone frequency, in Hz.
wrong_choice_tone_dur = 250;                                                %Trial start tone duration, in milliseconds.
timeout_duration = 5;                                                       %Set the timeout duration, in seconds.

%% Clean up the workspace.
clc;                                                                        %Clear the command window.
close all force;                                                            %Close any open figures.
fclose all;                                                                 %Close any open data files.

%% Connect to the OmniTrak Controller.
[ctrl, device_list] = Connect_OmniTrak;                                     %Connect to a Vulintus device.
if ~any(strcmpi(device_list,'OT-CC')) || ...
        sum(strcmpi(device_list,'OT-NP')) < 2                               %If an OmniTrak Controller with two nosepokes isn't found...
    ctrl.otsc.close();                                                      %Close the connection.
    error(['ERROR IN %s: This demo requires an OmniTrak Controller'...
        'connected to two nosepokes or pellet receivers.'],...
         upper(mfilename));                                                 %Throw an error.
end
port_devices = {ctrl.otmp.port.sku};                                        %Fetch the device types connected to the controller ports.
port_i = find(strcmpi(port_devices,'OT-NP'));                               %Find all nosepoke indices.
port_i = port_i(1:2);                                                       %Assume the first two nosepokes we find are ones we'll use.
nosepoke_status = zeros(1,2);                                               %Create a matrix to hold the nosepoke status.

%% Set up the light and tone stimuli.
for i = port_i                                                              %Step through the nosepokes.
    ctrl.cue.index.set(1,1,'passthrough',i);                                %Set the cue light index to the first LED and the first queue index.
    ctrl.cue.rgbw.set(cue_colors(1,:)*255,'passthrough',i);                 %Set the first cue color.
    ctrl.cue.index.set(1,2,'passthrough',i);                                %Set the cue light index to the first LED and the second queue index.
    ctrl.cue.rgbw.set(cue_colors(2,:)*255,'passthrough',i);                 %Set the second cue color.
    ctrl.tone.index.set(1,'passthrough',i);                                 %Set the tone queue index to the first tone.
    ctrl.tone.freq.set(trial_start_tone_freq,'passthrough',i);              %Set the tone frequency.
    ctrl.tone.dur.set(trial_start_tone_dur,'passthrough',i);                %Set the tone duration.
    ctrl.tone.index.set(2,'passthrough',i);                                 %Set the tone queue index to the second tone.
    ctrl.tone.freq.set(response_start_tone_freq,'passthrough',i);           %Set the tone frequency.
    ctrl.tone.dur.set(response_start_tone_dur,'passthrough',i);             %Set the tone duration.
    ctrl.tone.index.set(3,'passthrough',i);                                 %Set the tone queue index to the third tone.
    ctrl.tone.freq.set(wrong_choice_tone_freq,'passthrough',i);             %Set the tone frequency.
    ctrl.tone.dur.set(wrong_choice_tone_dur,'passthrough',i);               %Set the tone duration.
    ctrl.cue.off('passthrough',i);                                          %Turn off any existing cue light.
end

    
%% Create a simple graphical display.
fig = uifigure;                                                             %Create a figure.
ax = axes('parent',fig);                                                    %Create axes on that figure.
hold(ax,'on');                                                              %Hold the axes for multiple plot objects.

xy = [sind(0:10:360); cosd(0:10:360)]';                                     %Create coordinates for a circle.
plot_h = zeros(2,1);                                                        %Create a matrix to hold plot object handles.
plot_h(1) = fill(xy(:,1) - 1.5, xy(:,2), 'w', 'parent', ax);                %Create the left nosepoke indicator.
plot_h(2) = fill(xy(:,1) + 1.5, xy(:,2), 'w', 'parent', ax);                %Create the right nosepoke indicator.
set(ax,'XLim',[-3,3],'YLim',[-1.5,1.5],'DataAspectRatio',[1,1,1]);          %Adjust the axes scaling.

%% Set up the trial timing.
next_trial = datetime('now') + seconds(10);                                 %Start the first trial in 10 seconds.
cue_off = [];                                                               %Create a timer for turning the cue off.
response_start = [];                                                        %Create a timer for the start of the response window.
response_stop = [];                                                         %Create a timer for the end of the response window.

ctrl.otsc.clear();                                                          %Clear any residual values from the serial line.

%% Loop until the user closes the figure.
while ishandle(fig)                                                         %Loop until the user closes the figure.
    
    % Check for nosepokes.
    change_flag = false;                                                    %Keep track of whether any nosepoke values changed.
    for i = 1:2                                                             %Step through the nosepokes.
        [~, blk] = ctrl.irdet.bits('passthrough',port_i(i));                %Fetch the current state for each nosepoke.
        if blk ~= nosepoke_status(i)                                        %If the nosepoke status changed...
            set(plot_h(i),'FaceColor',[1, 1, 1] - double(blk)*[0, 1, 1]);   %Update the corresponding plot object color.
            nosepoke_status(i) = blk;                                       %Update the nosepoke status.
            change_flag = true;                                             %Set the change flag to true.
        end
    end
    
    %If a nosepoke is detected...
    if change_flag && any(nosepoke_status == 1)                             %If a nosepoke is blocked...
        if ~isempty(response_stop)                                          %If we're in the response window...
            if nosepoke_status(cur_target(1)) == 1                          %If the subject responded to the correct side.
                ctrl.feed.cur_feeder.set(cur_target(1));                    %Set the feeder side.
                ctrl.feed.start();                                          %Start a feeding.
                fprintf(1,'CORRECT RESPONSE - FEEDING\n');                  %Print a message to the command window.
            else                                                            %Otherwise...
                ctrl.tone.on(3,'passthrough',port_i(cur_target(2)));        %Play the punishment tone.
                fprintf(1,'INCORRECT RESPONSE - TIMEOUT\n');                %Print a message to the command window.
            end
            for i = port_i                                                  %Step through the nosepokes.
                ctrl.cue.off('passthrough',i);                              %Turn off the cue (on both nosepokes).
            end         
            response_stop = [];                                             %Reset the response window end timer.
        else                                                                %Otherwise, if we're not in the response window.
            fprintf(1,'PREEMPTED TRIAL - TIMEOUT\n');                       %Print a message to the command window.
            for i = 1:2                                                     %Step through the nosepokes.
                if nosepoke_status(i) == 1                                  %If the nosepoke is blocked...
                    ctrl.tone.on(3,'passthrough',port_i(i));                %Play the punishment tone.
                end
                ctrl.cue.off('passthrough',i);                              %Turn off any cue light.
            end
            next_trial = max(datetime('now')+seconds(timeout_duration),...
                next_trial);                                                %Reset the trial start timer.
        end
        cue_off = [];                                                       %Reset the cue duration timer.  
        response_start = [];                                                %Reset the response window start timer.
    end

    %If it's time to start a new trial...
    if datetime('now') > next_trial                                         %If it's time to start the next trial...
        cur_stim = randperm(2);                                             %Randomly pick a stimulus.
        cur_target = randperm(2);                                           %Randomly pick a target side.
        for i = port_i                                                      %Step through the nosepokes.
            ctrl.cue.on(1,cur_stim(1),'passthrough',i);                     %Display the cue on both sides.
            ctrl.tone.on(1,'passthrough',i);                                %Play the trial start tone.
        end
        cue_off = next_trial + seconds(cue_duration);                       %Set the cue off timer.
        next_trial = next_trial + seconds(inter_trial_interval);            %Set the next trial start time.
    end

    %If a trial is running and it's time to turn off the light cue...
    if ~isempty(cue_off) && datetime('now') > cue_off                       %If it's time to turn the cue light off... 
        for i = port_i                                                      %Step through the nosepokes.
            ctrl.cue.off('passthrough',i);                                  %Turn off the cue (on both nosepokes).
        end
        cur_delay = response_delay(1) + rand*range(response_delay);         %Calculate a random response delay.
        response_start = cue_off + seconds(cur_delay);                      %Set the response window start.
        cue_off = [];                                                       %Reset the cue timer.        
    end

    %If the set delay has passed and it's time for the subject to choose a response...
    if ~isempty(response_start) && datetime('now') > response_start         %If it's time to start the response window.
        ctrl.cue.on(1,cur_stim(1),'passthrough',port_i(cur_target(2)));     %Turn on the cue OPPOSITE the target nosepoke.
        ctrl.cue.on(1,cur_stim(2),'passthrough',port_i(cur_target(1)));     %Turn on the non-cue on the target nosepoke.
        for i = port_i                                                      %Step through the nosepokes.
            ctrl.tone.on(2,'passthrough',i);                                %Play the response window start tone.
        end
        response_stop = response_start + seconds(response_window);          %Set the end of the response window.
        response_start = [];                                                %Reset the response window start timer.        
    end

    %If the subject didn't respond...
    if ~isempty(response_stop) && datetime('now') > response_stop           %If the subject didn't respond...
        for i = port_i                                                      %Step through the nosepokes.
            ctrl.cue.off('passthrough',i);                                  %Turn off the cue (on both nosepokes).
            ctrl.tone.on(3,'passthrough',i);                                %Play the punishment tone.
        end
        next_trial = max(datetime('now')+seconds(timeout_duration),...
            next_trial);                                                    %Reset the trial start timer.
        fprintf(1,'NO RESPONSE - TIMEOUT\n');                               %Print a message to the command window.
        response_stop = [];                                                 %Reset the response window end timer.
    end

    pause(0.05);                                                            %Pause for 50 milliseconds to keep from maxing out the processor.

end

ctrl.otsc.clear();                                                          %Clear any residual values from the serial line.
ctrl.otsc.close();                                                          %Close the serial connection.
