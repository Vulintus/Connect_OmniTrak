function [ctrl, varargout] = Connect_OmniTrak(varargin)

%
% Connect_OmniTrak.m
% 
%   copyright 2021, Vulintus, Inc.
%
%   CONNECT_OMNITRAK establishes a direct serial connection between the 
%   computer and an OmniTrak device for wired control of Vulintus
%   behavioral testing equipment. The OmniTrak Serial Communication (OTSC)
%   protocol used by this function, and all Vulintus OmniTrak devices, is
%   open-source and available here:
%
%       https://github.com/Vulintus/OmniTrak_Serial_Communication
%
%   UPDATE LOG:
%   2021-09-14 - Drew Sloan - Function first created, adapted from
%                             Connect_MotoTrak.m.
%   2022-02-04 - Drew Sloan - Changed the OmniTrak Module Bus (OTMB) name
%                             to OmniTrak Module Port (OMTP) to indicate an
%                             unshared connection.
%   2023-09-27 - Drew Sloan - Merged the OTMP codes with the OmniTrak
%                             Serial Communication (OTSC) codes to create a
%                             single protocol for communicating with
%                             OmniTrak serial devices.
%   2024-06-05 - Drew Sloan - Created a beta version for testing.
%   2025-04-22 - Drew Sloan - Added the option to specify device types.
%

%Collated: 2025-06-19, 12:54:59

req_class_files =	{
		'Vulintus_OTSC_Stream_Class';
		'Vulintus_FIFO_Buffer';
		'Vulintus_Load_OTSC_Codes';
		'Vulintus_Load_OTSC_Packet_Info';
		'Vulintus_OTSC_Empty_Process';
		'Vulintus_OTSC_Parse_Packet';
		'Vulintus_OTSC_Passthrough_Commands';
		'Vulintus_OTSC_Transaction';
		'Vulintus_Serial_Basic_Functions';
		'Vulintus_Return_Data_Type_Size';
		'cprintf';
				};                                                          %Required classes and class-called functions.
Vulintus_Check_Required_Classes(req_class_files);                           %Check for required classes.


port = [];                                                                  %Create a variable to hold the serial port.
msgbox = [];                                                                %Create a matrix to hold a msgbox handle.
ax = [];                                                                    %Create a matrix to hold an axes handle.
device = {};                                                                %Create a cell array to hold device types.
if datetime(version('-date')) > datetime('2019-09-17')                      %If the version is 2019b or newer...
    use_serialport = true;                                                  %Use the newer serialport functions by default.
else                                                                        %Otherwise...
    use_serialport = false;                                                 %Use the older serial functions by default.
end
varargout{1} = {};                                                          %Assume we will return zero device SKUs.
default_baudrate = 115200;                                                  %Set the default baudrate.
alternate_baudrates = [1000000, 2000000];                                   %Test alternative baudrates if the first connection attempt fails.

%Load the OmniTrak Serial Communication (OTSC) codes.
otsc_codes = Vulintus_Load_OTSC_Codes;

%Step through the optional input arguments and set any user-specified parameters.
for i = 1:2:length(varargin)                                                %Step through the optional input arguments
    switch lower(varargin{i})                                               %Switch among the recognized parameter names.
        case 'port'                                                         %If the parameter name was "port"...            
            port = upper(varargin{i+1});                                    %Use the specified serial port.
            if ~ischar(port) && ~startsWith(port,'COM')                     %If the specified port isn't a character array or the first 3 letters aren't "COM"...
                error('ERROR IN %s: The specified COM port is invalid.',...
                    upper(mfilename));                                      %Show an error.
            end
        case 'msgbox'                                                       %If the parameter name was "msgbox"...
            msgbox = varargin{i+1};                                         %Save the messagebox handle to write messages to.
            msgbox_type = get(msgbox,'type');                               %Grab the messagebox type.
            if strcmpi(msgbox_type,'uicontrol')                             %If the messagebox is a uicontrol...
                msgbox_type = get(msgbox,'style');                          %Grab the uicontrol style as the type.
            end
            if ~ishandle(msgbox) && ...
                    ~any(strcmpi(msgbox_type,{'listbox','uitextarea'}))     %If the specified handle is not a recognized messagebox...
                error(['ERROR IN %s: The specified MessageBox handle is'...
                    ' invalid.'], upper(mfilename));                        %Show an error.
            end 
        case 'axes'                                                         %If the parameter name was "axes"...
            ax = varargin{i+1};                                             %Save the axes handle to write messages to.
            if ~ishandle(ax) && ...
                    ~any(strcmpi(get(ax,'type'),{'axes','uiaxes'}))         %If the specified handle is not an axes...
                error(['ERROR IN %s: The specified axes handle is '...
                    'invalid.'], upper(mfilename));                         %Show an error.
            end
        case 'useserialport'                                                %If the parameter was "useserialport"...
                use_serialport = varargin{i+1};                             %Set the flag for using the new serialport function.
                if ~(isnumeric(use_serialport) && ...
                        any(use_serialport == [1,0])) && ...
                        ~(islogical(use_serialport) && ...
                        any(use_serialport == [true, false]))               %If the flag wasn't set to a 0 or 1...
                    error(['ERROR IN %s: The ''UseSerialPort'' value '...
                        'must be true (1) or false (0).'],...
                        upper(mfilename));                                  %Show an error.
                end
        case 'device'                                                       %If the parameter was "device"...
            device = varargin{i+1};                                         %Grab the device type.
            if ~ischar(device) && ~iscell(device)                           %If the input isn't a character or cell array.
                error(['ERROR IN %s: The specified device type must be '...
                    'a character or cell array!'], upper(mfilename));       %Show an error.
            end
            device = cellstr(device);                                       %Make sure the device is a cell array.  
        otherwise
            cprintf('err',['ERROR IN %s:  Property name not recognized!'...
                ' Optional input properties are:\n'], upper(mfilename));    %Show an error.
            str = {'port','msgbox','axes'};                                 %List the optional input arguments.
            for j = 1:length(str)                                           %Step through each optional input argument name.
                cprintf('err',['\t''' str{j} '''\n']);                      %Print the optional input argument name.
            end
            beep;                                                           %Beep to alert the user to an error.
            ctrl = [];                                                      %Set the function output to empty.
            return                                                          %Skip execution of the rest of the function.
    end
end

port = Vulintus_Serial_Select_Port(use_serialport, port, device);           %Call the port selection function with a specified port.

if isempty(port)                                                            %If no port was selected.
    warning('Connect_OmniTrak:NoPortChosen',...
        ['No serial port was chosen for Connect_OmniTrak. Connection ' ...
        'to the device was aborted.']);                                     %Show a warning.
    ctrl = [];                                                              %Set the function output to empty.
    return                                                                  %Skip execution of the rest of the function.
end

if ~isempty(msgbox) && ~isempty(ax)                                         %If both a msgbox and an axes are specified...
    ax = [];                                                                %Clear the axes handle.
    warning(['WARNING IN Connect_OmniTrak: Both a msgbox and an axes '...
        handle were specified. The axes handle will be ignored.']);         %Show a warning.
end

message = sprintf('Connecting to %s...', port);                             %Create the beginning of message to show the user.
t = 0;                                                                      %Create a dummy handle for a text label.
if ~isempty(msgbox)                                                         %If the user specified a msgbox...
    Add_Msg(msgbox,message);                                                %Show the Arduino connection status in the msgbox.
elseif ~isempty(ax)                                                         %If the user specified an axes...
    t = text(mean(xlim(ax)),mean(ylim(ax)),message,...
        'horizontalalignment','center',...
        'verticalalignment','middle',...
        'fontweight','bold',...
        'margin',5,...
        'edgecolor','k',...
        'backgroundcolor','w',...
        'parent',ax);                                                       %Create a text object on the axes.
    temp = get(t,'extent');                                                 %Grab the extent of the text object.
    temp = temp(3)/range(xlim(ax));                                         %Find the ratio of the text length to the axes width.
    set(t,'fontsize',0.6*get(t,'fontsize')/temp);                           %Scale the fontsize of the text object to fit the axes.
else                                                                        %Otherwise...
    waitbar = big_waitbar('title','Connecting to OmniTrak Device',...
        'string',sprintf('Connecting to %s...',port),...
        'value',0.25);                                                      %Create a waitbar figure.
end

try                                                                         %Try to open the serial port for communication.
    if use_serialport                                                       %If we're using the newer serialport functions...
        serialcon = serialport(port,default_baudrate,'Timeout',1);          %Set up the serial connection on the specified port.
    else                                                                    %Otherwise, if we're using the older serial functions...
        temp = instrfind('port',port);                                      %Check to see if the specified port is busy...
        if ~isempty(temp)                                                   %If an existing serial connection was found for this port...
            fclose(temp);                                                   %Close the busy serial connection.
            delete(temp);                                                   %Delete the existing serial connection.
        end
        serialcon = serial(port,'baudrate',default_baudrate);               %Set up the serial connection on the specified port.
        serialcon.Timeout = 1;                                              %Set the timeout.
        fopen(serialcon);                                                   %Open the serial port.
    end
catch err                                                                   %If no connection could be made to the serial port...
    error(['ERROR IN %s: Could not open a serial connection on port '...
        '''%s''.'],upper(mfilename),port);                                  %Show an error.
end

vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);               %Load the basic serial functions for either "serialport" or "serial".

%Verify that the device is using the OTSC protocol.
if ~isempty(ax) && ishandle(t)                                              %If progress is being shown in text on an axes...
    msg_handle = t;                                                         %Pass the text object handle.
elseif ~isempty(msgbox)                                                     %If progress is being shown in a msgbox...
    msg_handle = msgbox;                                                    %Pass the messagebox handle.
else                                                                        %Otherwise, if progress is being shown in a waitbar...
    msg_handle = waitbar;                                                   %Pass the waitbar handle.
end
pause(2);                                                                   %Pause for 100 milliseconds to give the device a chance to boot up.
otsc_flag = Vulintus_Serial_Comm_Verification(serialcon,...
        otsc_codes('REQ_COMM_VERIFY'), otsc_codes('COMM_VERIFY'),...
        otsc_codes('STREAM_ENABLE'), msg_handle);                           %Call the OTSC verification function.

if ~otsc_flag                                                               %If OTSC communication wasn't established...
    for b = alternate_baudrates                                             %Step through the other possible baudrates.
        serialcon.BaudRate = b;                                             %Change the serial baud rate.
        otsc_flag = Vulintus_Serial_Comm_Verification(serialcon,...
            otsc_codes('REQ_COMM_VERIFY'), otsc_codes('COMM_VERIFY'),...
            otsc_codes('STREAM_ENABLE'), msg_handle);                          %Call the OTSC verification function.
        if otsc_flag                                                        %If OTSC communication was established...
            break                                                           %Break out of the for loop.
        end
    end
end

if ~otsc_flag                                                               %If OTSC communication wasn't ultimately established...
    delete(serialcon);                                                      %Close the serial connection.
    if isempty(msgbox) && isempty(ax)                                       %If the user didn't specify a msgbox or axes...
        waitbar.close();                                                    %Close the waitbar.
    end
    error(['ERROR IN %s: Could not connect to the device on the '...
        'selected serial port ''%s''. The device is not communicating '...
        'using the Vulintus OTSC protocol.'],upper(mfilename),port);        %Show an error.
end
    
if vulintus_serial.bytes_available() > 0                                    %If there's data on the serial line.
    vulintus_serial.flush();                                                %Clear the input and output buffers.
end

ctrl = struct('port',port);                                                 %Create the output structure for the serial communication.
ctrl.stream = Vulintus_OTSC_Stream_Class(serialcon, otsc_codes);            %Create an instance of the Vulintus OTSC stream class.
ctrl = Vulintus_OTSC_Common_Functions(ctrl, default_baudrate);              %Load the common OTSC functions.

baudrate = ctrl.device.baud_rate.max();                                     %Grab the max baud rate for the device.
% if strcmpi(class(serialcon),'serial')                                       %If the serial object is the deprecated 'serial' type...
%     baudrate = min(baudrate,256000);                                        %Constrain the baudrate to 256 kHz.
% end
if baudrate > default_baudrate                                              %If the maximum baud rate is faster than the default...
    [new_baudrate, code] = ctrl.device.baud_rate.set(baudrate);             %Set the new baudrate.
    if isempty(new_baudrate)                                                %If no confirmation was returned...
        error(['ERROR IN %s: Attempt to set the serial baud rate to '...
            '%1.0f Hz failed! \n\tNo confirmation packet received from '...
            'the device.'],upper(mfilename),baudrate);                      %Show an error.
    elseif new_baudrate ~= baudrate || ...
            code ~= otsc_codes('REPORT_BAUDRATE')                           %If the baudrate did not get set correctly...
        error(['ERROR IN %s: Attempt to set the serial baud rate to '...
            '%1.0f Hz failed! \n\tFunction returned a reported baud '...
            'rate of %1.0f Hz.'],upper(mfilename),baudrate,new_baudrate);   %Show an error.
    end
end

[ctrl, devices] = Vulintus_Serial_Load_OTSC_Functions(ctrl);                %Load the OTSC functions for the connected device.


%Check for user-set aliases.
if isfield(ctrl,'nvm')                                                      %If the non-volatile memory functions are loaded...
    ctrl.device.userset_alias = ctrl.device.alias.userset.get();            %Grab the user-set alias for this device.
    ctrl.device.vulintus_alias = ctrl.device.alias.vulintus.get();          %Grab the Vulintus alias for this device.
    if any(ctrl.device.userset_alias == 255)                                %If the user-set alias isn't set...
        ctrl.device.userset_alias = [];                                     %Set the user-set alias to empty brackets.
    end
    if any(ctrl.device.vulintus_alias == 255)                               %If the Vulintus alias isn't set...
        ctrl.device.vulintus_alias = [];                                    %Set the Vulintus alias to empty brackets.
    end
    if isempty(ctrl.device.userset_alias) && ...
            ~isempty(ctrl.device.vulintus_alias)                            %If the user-set alias is empty, but the Vulintus alias is set...
        ctrl.device.userset_alias = ctrl.device.vulintus_alias;             %Use the Vulintus alias in lieu of an user-set alias.
    end
    if ~isempty(ctrl.device.userset_alias)                                  %If the user-set alias isn't empty...
        Vulintus_Serial_Port_Matching_File_Update(ctrl.port,...
            ctrl.device.name, ctrl.device.userset_alias);                   %Update the serial port matching file.
    end
end

ctrl.stream.fcn('UNKNOWN_BLOCK_ERROR') = ...
    @(src, varargin)Vulintus_OTSC_Process_Unknown_Block_Error(ctrl,...
    src, varargin{:});                                                      %Set the default "UNKNOWN_BLOCK_ERROR" process function.

if ~isempty(ax) && ishandle(t)                                              %If progress is being shown in text on an axes...
    pause(1);                                                               %Pause for one second.
    delete(t);                                                              %Delete the text object.
elseif isempty(msgbox)                                                      %If progress is being shown in a waitbar...
    pause(1);                                                               %Pause for one second.
    waitbar.close();                                                        %Close the waitbar.
end

vulintus_serial.flush();                                                    %Clear the input and output buffers.

varargout{1} = devices;                                                     %Return a list of the connected devices.


%% ************************************************************************
function icon = Vulintus_Behavior_Match_Icon(icon, alpha_map, fig_handle)

%
%Vulintus_Behavior_Match_Icon.m - Vulintus, Inc.
%
%   VULINTUS_BEHAVIOR_MATCH_ICON replaces transparent pixels in a uifigure
%   icon with the menubar color behind the icon.
%   
%   UPDATE LOG:
%   2024-02-28 - Drew Sloan - Function first created.
%

tb = uitoolbar(fig_handle);                                                 %Temporarily create a toolbar on the figure.
if ~isprop(tb,'BackgroundColor')                                            %If this version of MATLAB doesn't have the toolbar BackgroundColor property.
    return                                                                  %Skip the rest of the function.
end
back_color = tb.BackgroundColor;                                            %Grab the background color.
delete(tb);                                                                 %Delete the temporary toolbar.
alpha_map = double(1-alpha_map/255);                                        %Convert the alpha map to a 0-1 transparency.
for i = 1:size(icon,1)                                                      %Step through each row of the icon.
    for j = 1:size(icon,2)                                                  %Step through each column of the icon.
        if alpha_map(i,j) > 0                                               %If the pixel has any transparency...
            for k = 1:3                                                     %Step through the RGB elements.
                if alpha_map(i,j) == 1                                      %If the pixel is totally transparent...
                    icon(i,j,k) = uint8(255*back_color(k));                 %Set the pixel color to the background color directly.
                else                                                        %Otherwise...
                    icon(i,j,k) = icon(i,j,k) + ...
                        uint8(255*alpha_map(i,j)*back_color(k));        %   Add in the appropriate amount of background color.
                end
            end
        end
    end
end


%% ************************************************************************
function appdata_path = Vulintus_Set_AppData_Path(program)

%
%Vulintus_Set_AppData_Path.m - Vulintus, Inc.
%
%   This function finds and/or creates the local application data folder
%   for Vulintus functions specified by "program".
%   
%   UPDATE LOG:
%   2016-06-05 - Drew Sloan - Function created to replace within-function
%                             calls in multiple programs.
%   2025-02-03 - Drew Sloan - Moved the bulk of the code to a more
%                             generalized "Set_AppData_Local_Path" script.
%


appdata_path = Set_AppData_Local_Path('Vulintus',program);                  %Call the more general AppData path generator.

if strcmpi(program,'mototrak')                                              %If the specified function is MotoTrak.
    oldpath = Set_AppData_Local_Path('MotoTrak');                           %Create the expected name of the previous version appdata directory.
    if exist(oldpath,'dir')                                                 %If the previous version directory exists...
        files = dir(oldpath);                                               %Grab the list of items contained within the previous directory.
        for f = 1:length(files)                                             %Step through each item.
            if ~files(f).isdir                                             	%If the item isn't a directory...
                copyfile([oldpath, files(f).name],appdata_path,'f');        %Copy the file to the new directory.
            end
        end
        [status, msg] = rmdir(oldpath,'s');                                 %Delete the previous version appdata directory.
        if status ~= 1                                                      %If the directory couldn't be deleted...
            warning(['Unable to delete application data'...
                ' directory\n\n%s\n\nDetails:\n\n%s'],oldpath,msg);         %Show an warning.
        end
    end
end


%% ************************************************************************
function device = Vulintus_Load_OTSC_Device_IDs

%	Vulintus_Load_OTSC_Device_IDs.m
%
%	copyright, Vulintus, Inc.
%
%	OmniTrak Serial Communication (OTSC) library.
%
%	OTSC device IDs.
%
%	Library documentation:
%	https://github.com/Vulintus/OmniTrak_Serial_Communication
%
%	This function was programmatically generated: 2025-06-09, 07:46:01 (UTC)
%

device = dictionary;

device(30) = struct('sku', 'AD-BL', 'name', 'Arduino Nano 33 BLE');
device(29) = struct('sku', 'AD-IO', 'name', 'Arduino Nano 33 IoT');
device(5)  = struct('sku', 'HT-TH', 'name', 'HabiTrak Thermal Activity Tracker');
device(21) = struct('sku', 'MT-AP', 'name', 'MotoTrak Autopositioner');
device(6)  = struct('sku', 'MT-HL', 'name', 'MotoTrak Haptic Lever Module');
device(3)  = struct('sku', 'MT-HS', 'name', 'MotoTrak Haptic Supination Module');
device(17) = struct('sku', 'MT-IP', 'name', 'MotoTrak Isometric Pull Module (MT-IP)');
device(4)  = struct('sku', 'MT-LP', 'name', 'MotoTrak Lever Press Module');
device(11) = struct('sku', 'MT-PC', 'name', 'MotoTrak Pellet Carousel Module');
device(20) = struct('sku', 'MT-PP', 'name', 'MotoTrak Pellet Pedestal Module');
device(2)  = struct('sku', 'MT-PS', 'name', 'MotoTrak Passive Supination Module');
device(13) = struct('sku', 'MT-SQ', 'name', 'MotoTrak Squeeze Module');
device(27) = struct('sku', 'MT-ST', 'name', 'MotoTrak Spherical Treadmill Module');
device(10) = struct('sku', 'MT-WR', 'name', 'MotoTrak Water Reach Module');
device(19) = struct('sku', 'OT-3P', 'name', 'OmniTrak Three-Nosepoke Module');
device(1)  = struct('sku', 'OT-CC', 'name', 'OmniTrak Common Controller');
device(9)  = struct('sku', 'OT-LR', 'name', 'OmniTrak Liquid Receiver Module');
device(7)  = struct('sku', 'OT-NP', 'name', 'OmniTrak Nosepoke Module');
device(16) = struct('sku', 'OT-OA', 'name', 'OmniTrak Overhead Auditory Module');
device(22) = struct('sku', 'OT-PD', 'name', 'OmniTrak Pocket Door Module');
device(8)  = struct('sku', 'OT-PR', 'name', 'OmniTrak Pellet Receiver Module');
device(28) = struct('sku', 'OT-SC', 'name', 'OmniTrak Social Choice Module');
device(18) = struct('sku', 'OT-TH', 'name', 'OmniTrak Thermal Activity Tracking Module');
device(26) = struct('sku', 'PB-LA', 'name', 'VPB Linear Autopositioner');
device(23) = struct('sku', 'PB-LD', 'name', 'VPB Liquid Dispenser');
device(24) = struct('sku', 'PB-PD', 'name', 'VPB Pellet Dispenser');
device(15) = struct('sku', 'ST-AP', 'name', 'SensiTrak Arm Proprioception Module');
device(14) = struct('sku', 'ST-TC', 'name', 'SensiTrak Tactile Carousel Module');
device(12) = struct('sku', 'ST-VT', 'name', 'SensiTrak Vibrotactile Module');
device(25) = struct('sku', 'XN-RI', 'name', 'XNerve Replay IMU');


%% ************************************************************************
function ctrl = Vulintus_OTSC_BLE_Functions(ctrl, varargin)

% Vulintus_OTSC_BLE_Functions.m
% 
%   copyright 2025, Vulintus, Inc.
%
%   VULINTUS_OTSC_BLE_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have Bluetooth Low Energy (BLE) functionality.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2025-03-07 - Drew Sloan - Function first created.
%


%List the Vulintus devices that have BLE functions.
device_list = { 'AD-BL',...     %Arduino Nano 33 BLE.
                'AD-IO',...     %Arduino Nano 33 IoT.
                'HT-TH',...     %HabiTrak Thermal Activity Tracker.
                'XN-RI'};       %[private]

%If an cell arracy of connected devices was provided, match against the device list.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'ble')                                              %If there's a "ble" field in the control structure...
            ctrl = rmfield(ctrl,'ble');                                     %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%BLE status functions.
ctrl.ble = [];                                                              %Create a field to hold BLE functions.

% Connect to a Bluetooth Low Energy (BLE) device that is advertising with a 
% particular (local) name.
ble_connect_lookup = {  'name',         1;
                        'address',      2;
                        'uuid',         3;
                     };
ctrl.ble.connect = ...
    @(ctype, str, varargin)Vulintus_OTSC_Lookup_Match_Set(serialcon,...
    ctrl.stream.otsc_codes('BLE_CONNECT'),...
    ble_connect_lookup,...
    ctype,...
    {0, 'uint8'; length(str),'uint8'; str,'char'},...
    varargin{:});

% Disconnect from any currently connected Bluetooth Low Energy (BLE)
% device.
ctrl.ble.disconnect = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('BLE_DISCONNECT'),...
    varargin{:});

%Request the Bluetooth Low Energy (BLE) device connection status.
ctrl.ble.status = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_BLE_CONNECTED'),...
    'reply',{1,'uint8'},...
    varargin{:});             

%Request/set the current vibration pulse duration, in microseconds.
ctrl.ble.write = ...
    @(char_i,data,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('BLE_CHARACTERISTIC_WRITE'),...
    'data',{char_i,'uint8'; length(data),'uint8'; data,'uint8'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_Cage_Light_Functions(ctrl, varargin)

%Vulintus_OTSC_Cage_Light_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_OTSC_CAGE_LIGHT_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which can control overhead cage lights.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-04-23 - Drew Sloan - Function first created.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = { 'OT-3P',...
                'OT-CC'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'light')                                            %If there's a "light" field in the control structure...
            ctrl = rmfield(ctrl,'light');                                   %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Overhead cage light functions.
ctrl.light = [];                                                            %Create a field to hold overhead cage light functions.

%Turn on/off the overhead cage light.
ctrl.light.on = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAGE_LIGHT_ON'),...
    varargin{:});                                  
ctrl.light.off = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAGE_LIGHT_OFF'),...
    varargin{:});

%Request/set the RGBW values for the overhead cage light (0-255).
ctrl.light.rgbw.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CAGE_LIGHT_RGBW'),...
    'reply',{4,'uint8'},...
    varargin{:});               
ctrl.light.rgbw.set = ...
    @(rgbw,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAGE_LIGHT_RGBW'),...
    'data',{rgbw,'uint8'},...
    varargin{:});

%Request/set the overhead cage light duration, in milliseconds.
ctrl.light.dur.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CAGE_LIGHT_DUR'),...
    'reply',{1,'uint16'},...
    varargin{:});           
ctrl.light.dur.set = ...
    @(dur,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAGE_LIGHT_DUR'),...
    'data',{dur,'uint16'},...
    varargin{:});

    


%% ************************************************************************
function ctrl = Vulintus_OTSC_Capacitive_Sensor_Functions(ctrl, varargin)

%Vulintus_OTSC_Capacitive_Sensor_Functions.m - Vulintus, Inc., 2023
%
%   VULINTUS_OTSC_CAPACITIVE_SENSOR_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have capacitive detection sensors.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-07-25 - Drew Sloan - Function first created, adapted from
%                             "Vulintus_OTSC_Lick_Sensor_Functions.m".
%


%List the Vulintus devices that have capacitive sensor functions.
device_list = {'MT-PP','OT-NP','OT-3P'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'capsense')                                         %If there's a "capsense" field in the control structure...
            ctrl = rmfield(ctrl,'capsense');                                %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Capacitive sensor status functions.
ctrl.capsense = [];                                                         %Create a field to hold capacitive sensor functions.

%Request the current capacitive sensor status bitmask.
ctrl.capsense.bits = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_BITMASK'),...
    'reply',{1, 'uint32'; 1,'uint8'},...
    varargin{:});             

%Request/set the current capacitive sensor index.
ctrl.capsense.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CAPSENSE_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.capsense.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Request/set the current capacitive sensor sensitivity setting, normalized from 0 to 1.
ctrl.capsense.sensitivity.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_SENSITIVITY'),...
    'reply',{1, 'uint8'; 1,'single'},...
    varargin{:});     
ctrl.capsense.sensitivity.set = ...
    @(thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_SENSITIVITY'), ...
    'data',{thresh,'single'},...
    varargin{:});

%Reset the current capacitive sensor.
ctrl.capsense.reset = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_RESET'),...
    varargin{:});     


%List the Vulintus devices that have firmware-based (i.e. "analog") capacitive sensor functions.
device_list = {'OT-NP','OT-3P'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        return                                                              %Skip execution of the rest of the function.
    end
end

% Request the current capacitance sensor reading, filtered or unfiltered
% in ADC ticks or clock cycles.
ctrl.capsense.value = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_VALUE'),...
    'reply',{1,'uint32'; 1,'uint8'; 1, 'uint8'; 2,'uint16'},...
    varargin{:});

%Request the minimum and maximum values of the current capacitive sensor's history.
ctrl.capsense.minmax = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_MINMAX'),...
    'reply',{1, 'uint8'; 2,'uint16'},...
    varargin{:});                 

%Request/set the current capacitive sensor fixed threshold setting, in ADC ticks or clock cycles.
ctrl.capsense.thresh.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_THRESH_FIXED'),...
    'reply',{1, 'uint8'; 1,'uint16'},...
    varargin{:});    
ctrl.capsense.thresh.set = ...
    @(thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_THRESH_FIXED'),...
    'data',{thresh,'uint16'},...
    varargin{:});

% Request/set the minimum signal range for positive detection with the 
% current capacitive sensor.
ctrl.capsense.min_range.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_MIN_RANGE'),...
    'reply',{1, 'uint8'; 1,'uint16'},...
    varargin{:});    
ctrl.capsense.min_range.set = ...
    @(min_range,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_MIN_RANGE'),...
    'data',{min_range,'uint16'},...
    varargin{:});

%Request/set the current capacitive sensor auto-thresholding setting (0 = fixed, 1 = autoset).
thresh_types = {    'fixed',     0;      
                    'auto',      1;
               };
ctrl.capsense.thresh.type.get = ...
    @(varargin)Vulintus_OTSC_Lookup_Match_Request(serialcon,...
    ctrl.stream.otsc_codes('REQ_CAPSENSE_THRESH_AUTO'),...
    ctrl.stream.otsc_codes('CAPSENSE_THRESH_AUTO'),...
    thresh_types, ...
    {2, 'uint8'},...
    varargin{:});
ctrl.capsense.thresh.type.set = ...
    @(mode,varargin)Vulintus_OTSC_Lookup_Match_Set(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_THRESH_AUTO'),...
    thresh_types,...
    mode,...
    {0,'uint8'},...
    varargin{:});

%Request/set the current capacitive sensor reset timeout duration, in milliseconds (0 = no time-out reset).
ctrl.capsense.reset_timeout.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_RESET_TIMEOUT'),...
    'reply',{1, 'uint8'; 1,'uint16'},...
    varargin{:});    
ctrl.capsense.reset_timeout.set = ...
    @(thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_RESET_TIMEOUT'),...
    'data',{thresh,'uint16'},...
    varargin{:});

%Request/set the current capacitive sensor repeated measurement sample size.
ctrl.capsense.sample_size.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CAPSENSE_SAMPLE_SIZE'),...
    'reply',{2,'uint8'},...
    varargin{:});    
ctrl.capsense.sample_size.set = ...
    @(sample_size,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_SAMPLE_SIZE'),...
    'data',{sample_size,'uint8'},...
    varargin{:});

% Request/set the current capacitive sensor filter high- and low-pass 
% cutoff frequencies, in Hz.
ctrl.capsense.filter.highpass.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CAPSENSE_HIGHPASS_CUTOFF'),...
    'reply',{1, 'uint8'; 1,'single'},...
    varargin{:});             
ctrl.capsense.filter.highpass.set = ...
    @(freq,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_HIGHPASS_CUTOFF'),...
    'data',{freq,'single'},...
    varargin{:});
ctrl.capsense.filter.lowpass.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CAPSENSE_LOWPASS_CUTOFF'),...
    'reply',{1, 'uint8'; 1,'single'},...
    varargin{:});             
ctrl.capsense.filter.lowpass.set = ...
    @(freq,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CAPSENSE_LOWPASS_CUTOFF'),...
    'data',{freq,'single'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_Common_Functions(ctrl, default_baudrate)

% Vulintus_OTSC_Common_Functions.m - Vulintus, Inc., 2022
%
%   VULINTUS_OTSC_COMMON_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to a function structure for control of 
%   Vulintus OmniTrak devices over the serial line.
%  
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2022-02-25 - Drew Sloan - Function first created, adapted from
%                             MotoTrak_Controller_V2pX_Serial_Functions.m.
%   2022-05-24 - Drew Sloan - Added a 'verbose' output option to the
%                             "read_stream" function.
%   2023-09-27 - Drew Sloan - Merged the OTSC protocol into the OmniTrak
%                             Serial Communication (OTSC) protocol and
%                             changed this function name from 
%                             "OTSC_Common_Serial_Functions" to
%                             "Vulintus_OTSC_Common_Functions".
%   2023-12-07 - Drew Sloan - Updated calls to "Vulintus_Serial_Request" to
%                             allow multi-type responses.
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2025-04-09 - Drew Sloan - Converted the "stream" field to a the
%                             Vulintus OTSC Stream class.
%

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.
vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);               %Load the basic serial functions for either "serialport" or "serial".

%List the firmware program modes (must match definition in "Vulintus_OTSC_Handler.h".
firmware_program_modes = {
    'idle',     0;
    'session',  1;
    'trial',    2;
    };

%Serial line management functions.
ctrl.otsc = [];                                                             %Create a field to hold OTSC functions.

%Clear the serial line.
ctrl.otsc.clear = ...
    @(varargin)Vulintus_OTSC_fcn_CLEAR(vulintus_serial.bytes_available,...
    vulintus_serial.flush,...\
    ctrl.stream,...
    varargin{:});    

%Verify OTSC communication.
ctrl.otsc.verify = ...
    @(varargin)Vulintus_Serial_Comm_Verification(serialcon,...
    ctrl.stream.otsc_codes('REQ_COMM_VERIFY'),...
    ctrl.stream.otsc_codes('COMM_VERIFY'),...
    varargin{:});         

%Device information functions.
ctrl.device = [];                                                           %Create a field to hold device info.

%Request the device ID number.
ctrl.device.id = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_DEVICE_ID'),...
    'reply',{1,'uint16'},...
    varargin{:});                

%Serial baud rate control.
ctrl.device.baud_rate.max = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_MAX_BAUDRATE'),...
    'reply',{1,'uint32'},...
    varargin{:});         
ctrl.device.baud_rate.set = ...
    @(baudrate,varargin)Vulintus_OTSC_fcn_SET_BAUDRATE(serialcon,...
    ctrl.stream.otsc_codes('SET_BAUDRATE'), baudrate, varargin{:});

%Serial baud rate test.
ctrl.device.baud_rate.test.receive = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_BAUDRATE_TEST'),...
    'reply',{256,'uint8'},...
    varargin{:});
ctrl.device.baud_rate.test.send = ...
    @(count,varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('BAUDRATE_TEST'),...
    'data',{count,'uint8'; 0:(count-1),'uint8'},...
    'reply',{2,'uint8'},...
    varargin{:});    

%Request the firmware filename, upload date, or upload time.
ctrl.device.firmware.filename = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_FW_FILENAME'),...
    'reply',{NaN,'char'}, ...
    varargin{:});                
ctrl.device.firmware.date = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_FW_DATE'),...
    'reply',{NaN,'char'},...
    varargin{:});                          
ctrl.device.firmware.time = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_FW_TIME'),...
    'reply',{NaN,'char'},...
    varargin{:});

%Request the circuit board version number.
ctrl.device.pcb_version = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_BOARD_VER'),...
    'reply',{2,'uint8'},...
    varargin{:});          

%Request/set the current firmware program mode.
ctrl.device.firmware.mode.get = ...
    @(varargin)Vulintus_OTSC_Lookup_Match_Request(serialcon,...
    ctrl.stream.otsc_codes('REQ_PROGRAM_MODE'),...
    ctrl.stream.otsc_codes('PROGRAM_MODE'),...
    firmware_program_modes,...
    {1, 'uint8'},...
    varargin{:});
ctrl.device.firmware.mode.set = ...
    @(mode,varargin)Vulintus_OTSC_Lookup_Match_Set(serialcon,...
    ctrl.stream.otsc_codes('PROGRAM_MODE'),...
    firmware_program_modes,...
    mode,...
    {0,'uint8'},...
    varargin{:});

%Request the device microcontroller unique ID number.
ctrl.device.mcu_serialnum = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MCU_SERIALNUM'),...
    'reply',{NaN,'uint8'},...
    varargin{:});                    

%Request/set the user-set device alias.
ctrl.device.alias.userset.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_USERSET_ALIAS'),...
    'reply',{NaN,'char'},...
    varargin{:});    
ctrl.device.alias.userset.set = ...
    @(alias,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('USERSET_ALIAS'),...
    'data',{length(alias),'uint8'; alias,'char'},...
    varargin{:}); 
                 
%Request/set the Vulintus alias (adjective/noun serial number) for the device.
ctrl.device.alias.vulintus.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_VULINTUS_ALIAS'),...
    'reply',{NaN,'char'},...
    varargin{:});          
ctrl.device.alias.vulintus.set = ...
    @(alias,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VULINTUS_ALIAS'),...
    'data',{length(alias),'uint8'; alias,'char'},...
    varargin{:});

% Request the microcontroller's current millisecond and microsecond clock
% readings.
ctrl.device.clocks.get = ...
    @(varargin)Vulintus_OTSC_fcn_Synchronize_Clocks(serialcon,...
    ctrl.stream.otsc_codes('REQ_MILLIS_MICROS'), varargin{:});                                  

%Close and delete the serial connection.
ctrl.otsc.close = ...
    @()Vulintus_Serial_Close(serialcon,...
    @()ctrl.stream.enable(0),...
    @()ctrl.device.baud_rate.set(default_baudrate),...
    vulintus_serial.flush);
ctrl.close = ctrl.otsc.close;


%*****************************************************************************************************************************************************
%Clear the serial line.
function Vulintus_OTSC_fcn_CLEAR(bytes_available_fcn, flush_fcn, stream, varargin)
if nargin > 3                                                               %If there were any input arguments...
    timeout = varargin{1};                                                  %The time-out duration is the first input argument.
    flush_timer = tic;                                                      %Start a timer.
    while toc(flush_timer) < timeout                                        %Loop until the end of the timeout.
        if bytes_available_fcn()                                            %If there are any bytes available...
            flush_fcn();                                                    %Flush the serial line.
        end
    end
end
flush_fcn();                                                                %Flush the serial line.
stream.clear();                                                             %Clear the stream buffers.


%*****************************************************************************************************************************************************
%Set the baud rate for serial communication between the device and the computer.
function varargout = Vulintus_OTSC_fcn_SET_BAUDRATE(serialcon, code, baudrate, varargin)
target_device = 0;                                                          %Set the default target to 0 (primary controller).
for i = 1:length(varargin)                                                  %Step through the optional input arguments.
    if ischar(varargin{i}) && ...
            strcmpi(varargin{i},'passthrough') && ...
            length(varargin) > i                                            %If the input is "passthrough"...
        target_device = varargin{i+1};                                      %Set the target device.
    end
end
baudrate = baudrate + bitshift(target_device,28);                           %Encode the target index in top 4 bits of the MSB.
[new_baudrate, code] = Vulintus_OTSC_Transaction(serialcon, code,...
    'data',{baudrate,'uint32'},...
    'reply',{1,'uint32'},...
    varargin{:});                                                           %Send the baudrate with the optional arugments.
if target_device == 0 && new_baudrate == baudrate                           %If the target was primary controller.
    switch class(serialcon)                                                 %Switch between the types of serial connections.
        case 'internal.Serialport'                                          %Newer serialport functions.
            serialcon.BaudRate = baudrate;                                  %Set the baud rate on the serial connection.    
        case 'serial'                                                       %Older, deprecated serial functions.
            fclose(serialcon);                                              %Close the serial port.
            serialcon.BaudRate = baudrate;                                  %Set the baud rate on the serial connection.    
            fopen(serialcon);                                               %Reopent the serial connection.
    end
    vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);           %Load the basic serial functions for either "serialport" or "serial".    
    vulintus_serial.flush();                                                %Flush the serial line.
end
varargout = {new_baudrate, code};                                           %Set the variable output arguments.


%*****************************************************************************************************************************************************
%Fetch the current millis() and micros() clock times from the controller/module and recording the corresponding computer clock time.
function varargout = Vulintus_OTSC_fcn_Synchronize_Clocks(serialcon, code, varargin)
serial_date = convertTo(datetime,'datenum');                                %Grab the current serial data number.
if isempty(varargin)                                                        %If there's no optional input arguments...    
    [reply, code] = Vulintus_OTSC_Transaction(serialcon, code,...
        'reply',{2,'uint32'});                                              %Request the current clock readings with no optional arugments.
else                                                                        %Otherwise...
    [reply, code] = Vulintus_OTSC_Transaction(serialcon, code,...
        'reply',{2,'uint32'},...
        varargin{:});                                                       %Request the current clock readings with the optional arugments.
end
if ~isempty(reply)                                                          %If a reply was returned...
    reply = [serial_date, double(reply)];                                   %Add the serial date number to the returned values.
end
varargout = {reply, code};                                                  %Set the variable output arguments.


%% ************************************************************************
function ctrl = Vulintus_OTSC_Cue_Light_Functions(ctrl, varargin)

%Vulintus_OTSC_Cue_Light_Functions.m - Vulintus, Inc., 2023
%
%   VULINTUS_OTSC_CUE_LIGHT_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have cue light capabilities.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2023-10-03 - Drew Sloan - Function first created.
%   2023-12-07 - Drew Sloan - Updated calls to "Vulintus_Serial_Request" to
%                             allow multi-type responses.
%   2024-01-31 - Drew Sloan - Added optional input arguments for
%                             passthrough commands.
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%                             Changed the function name from 
%                             "Vulintus_OTSC_Light_Functions" to
%                             "Vulintus_OTSC_Cue_Light_Functions".
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = { 'MT-PP',...
                'OT-3P',...
                'OT-NP',...
                'OT-PR',...
                'OT-LR'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'cue')                                              %If there's a "cue" field in the control structure...
            ctrl = rmfield(ctrl,'cue');                                     %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Cue light functions.
ctrl.cue = [];                                                              %Create a field to hold cue light functions.

%Show the specified cue light.
ctrl.cue.on = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUE_LIGHT_ON'),...
    'data',{i,'uint8'},...
    varargin{:});                         

%Turn off any active cue light.
ctrl.cue.off = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUE_LIGHT_OFF'),...
    varargin{:});         

%Request/set the current cue light index.
ctrl.cue.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CUE_LIGHT_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.cue.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUE_LIGHT_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Request/set the current cue light queue index.
ctrl.cue.queue_index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CUE_LIGHT_QUEUE_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});   
ctrl.cue.queue_index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUE_LIGHT_QUEUE_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Request/set the RGBW values for the current cue light (0-255).
ctrl.cue.rgbw.get =...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CUE_LIGHT_RGBW'),...
    'reply',{4,'uint8'},...
    varargin{:});       
ctrl.cue.rgbw.set = ...
    @(rgbw,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUE_LIGHT_RGBW'),...
    'data',{rgbw,'uint8'},...
    varargin{:});

%Request/set the current cue light duration, in milliseconds.
ctrl.cue.dur.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CUE_LIGHT_DUR'),...
    'reply',{1,'uint16'},...
    varargin{:});         
ctrl.cue.dur.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUE_LIGHT_DUR'),...
    'data',{i,'uint16'},...
    varargin{:});

     


%% ************************************************************************
function ctrl = Vulintus_OTSC_Dispenser_Functions(ctrl, varargin)

%Vulintus_OTSC_Dispenser_Functions.m - Vulintus, Inc., 2022
%
%   VULINTUS_OTSC_DISPENSER_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to a function structure for control of 
%   Vulintus OmniTrak devices over the serial line. These functions are 
%   designed to be used with the "serialport" object introduced in MATLAB 
%   R2019b and will not work with the older "serial" object communication.
%
%   UPDATE LOG:
%   2023-10-02 - Drew Sloan - Function first created, split off from
%                             "Vulintus_OTSC_Common_Functions.m".
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = {'MT-PP','OT-3P','OT-CC'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'feed')                                             %If there's a "feed" field in the control structure...
            ctrl = rmfield(ctrl,'feed');                                    %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Pellet/liquid dispenser control functions.
ctrl.feed = [];                                                             %Create a field to hold feeder functions.

%Trigger dispensing on the currently-selected dispenser.
ctrl.feed.start = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TRIGGER_FEEDER'),...
    varargin{:});                         

%Immediately shut off any active dispensing trigger.
ctrl.feed.stop = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('STOP_FEED'),...
    varargin{:});                                                  

%Request/set the current dispenser index.
ctrl.feed.cur_feeder.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_CUR_FEEDER'),...
    'reply',{1,'uint8'},...
    varargin{:});      
ctrl.feed.cur_feeder.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('CUR_FEEDER'),...
    'data',{i,'uint8'},...
    varargin{:});                                                 

%Request/set the current dispenser trigger duration, in milliseconds.
ctrl.feed.trig_dur.get = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_FEED_TRIG_DUR'),...
    'reply',{1,'uint16'},...
    varargin{:});
ctrl.feed.trig_dur.set = @(dur)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('FEED_TRIG_DUR'),...
    'data',{dur,'uint16'},...
    varargin{:});

%Enable or disable pellet detection.
ctrl.feed.detect.enable = ...
    @(enable,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('PELLET_DETECT_ENABLE'),...
    'data',{enable,'uint8'},...
    varargin{:});    

%Command the current dispenser to prepare a reward for dispensing (i.e. reload a pellet).
ctrl.feed.reload.start = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('DISPENSER_RELOAD'),...
    varargin{:});    

%Request/set the current maximum number of reload attempts.
ctrl.feed.reload.max_attempts.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MAX_RELOAD_ATTEMPTS'),...
    'reply',{2,'uint8'},...
    varargin{:});
ctrl.feed.reload.max_attempts.set = ...
    @(num_attempts,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MAX_RELOAD_ATTEMPTS'),...
    'data',{num_attempts,'uint8'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_Haptic_Driver_Functions(ctrl, varargin)

% Vulintus_OTSC_Haptic_Driver_Functions.m
% 
%   copyright 2024, Vulintus, Inc.
%
%   VULINTUS_OTSC_HAPTIC_DRIVER_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have haptic or vibration drivers.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-10-22 - Drew Sloan - Function first created.
%   2024-11-21 - Drew Sloan - Replaced bespoke mode-setting functions with
%                             new generalized lookup-matching functions.
%


%List the Vulintus devices that have haptic driver functions.
device_list = {'ST-VT'};

%If an cell arracy of connected devices was provided, match against the device list.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'haptic')                                           %If there's a "haptic" field in the control structure...
            ctrl = rmfield(ctrl,'haptic');                                  %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Haptic driver status functions.
ctrl.haptic = [];                                                           %Create a field to hold haptic driver functions.

%Immediately start/stop the vibration pulse train.
ctrl.haptic.start = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('START_VIB'),...
    varargin{:});
ctrl.haptic.stop = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('STOP_VIB'),...
    varargin{:});   

%Request/set the current haptic index.
ctrl.haptic.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_VIB_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.haptic.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Request/set the current vibration pulse duration, in microseconds.
ctrl.haptic.pulse.dur.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_VIB_DUR'),...
    'reply',{1,'uint32'},...
    varargin{:});    
ctrl.haptic.pulse.dur.set = ...
    @(dur,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_DUR'),...
    'data',{dur,'uint32'},...
    varargin{:});

%Request/set the current vibration train onset-to-onset inter-pulse interval, in microseconds.
ctrl.haptic.pulse.ipi.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_VIB_IPI'),...
    'reply',{1,'uint32'},...
    varargin{:});    
ctrl.haptic.pulse.ipi.set = ...
    @(ipi,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_IPI'),...
    'data',{ipi,'uint32'},...
    varargin{:});

%Request/set the current vibration train duration, in number of pulses.
ctrl.haptic.pulse.num.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_VIB_N_PULSE'),...
    'reply',{1,'uint16'},...
    varargin{:});    
ctrl.haptic.pulse.num.set = ...
    @(num_pulses,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_N_PULSE') ,...
    'data',{num_pulses,'uint16'},...
    varargin{:});

%Request/set the current vibration train skipped pulses starting and stopping index.
ctrl.haptic.pulse.gap.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_VIB_GAP'),...
    'reply',{2,'uint16'},...
    varargin{:});    
ctrl.haptic.pulse.gap.set = ...
    @(gap_startstop,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_GAP'),...
    'data',{gap_startstop,'uint16'},...
    varargin{:});

%Enable/disable vibration tone masking.
ctrl.haptic.masking.disable = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_MASK_ENABLE'),...
    'data',{0,'uint8'},...
    varargin{:});
ctrl.haptic.masking.enable = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_MASK_ENABLE'),...
    'data',{1,'uint8'},...
    varargin{:});

%Set/report the current tone repertoire index for the masking tone.
ctrl.haptic.masking.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_VIB_MASK_TONE_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.haptic.masking.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('VIB_MASK_TONE_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Request/set the the current vibration task mode.
haptic_mode_lookup = {  'silent_burst',         0;
                        'silent_gap',           1;
                        'dummy_burst',          2;
                        'dummy_gap',            3;
                        'dummy_burst_catch',    4;
                     };
ctrl.haptic.pulse.mode.get = ...
    @(varargin)Vulintus_OTSC_Lookup_Match_Request(serialcon,...
    ctrl.stream.otsc_codes('REQ_VIB_TASK_MODE'),...
    ctrl.stream.otsc_codes('VIB_TASK_MODE'),...
    haptic_mode_lookup,...
    {2, 'uint8'},...
    varargin{:});
ctrl.haptic.pulse.mode.set = ...
    @(mode,varargin)Vulintus_OTSC_Lookup_Match_Set(serialcon,...
    ctrl.stream.otsc_codes('VIB_TASK_MODE'),...
    haptic_mode_lookup,...
    mode,...
    {0, 'uint8'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_IR_Detector_Functions(ctrl, varargin)

%Vulintus_OTSC_IR_Detector_Functions.m - Vulintus, Inc., 2023
%
%   VULINTUS_OTSC_IR_Detector_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have IR detector sensors.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2023-10-02 - Drew Sloan - Function first created, split off from
%                             "Vulintus_OTSC_Common_Functions.m".
%   2023-12-07 - Drew Sloan - Updated calls to "Vulintus_Serial_Request" to
%                             allow multi-type responses.
%   2024-01-31 - Drew Sloan - Added optional input arguments for
%                             passthrough commands.
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%                           - Renamed script from
%                             "Vulintus_OTSC_Nosepoke_Functions" to 
%                             "Vulintus_OTSC_IR_Detector_Functions".
%


%List the Vulintus devices that use these functions.
device_list = { 'MT-PP',...
                'OT-3P',...
                'OT-NP',...
                'OT-PR',...
                'OT-LR'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'irdet')                                            %If there's a "ir" field in the control structure...
            ctrl = rmfield(ctrl,'irdet');                                   %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%IR detecto status functions.
ctrl.irdet = [];                                                            %Create a field to hold IR detector functions.

%Request the current IR detector status bitmask.
ctrl.irdet.bits = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_BITMASK'),...
    'reply',{1,'uint32'; 1,'uint8'},...
    varargin{:});                                               

%Request the current IR detector analog reading.
ctrl.irdet.adc = ...
   @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_ADC'),...
   'reply',{1, 'uint32'; 2,'uint16'},...
   varargin{:});        

%Request the minimum and maximum ADC values of the IR detector sensor history, in ADC ticks.
ctrl.irdet.minmax = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_MINMAX'),...
    'reply',{2,'uint16'},...
    varargin{:});                                                           

%Request/set the current IR detector threshold setting, normalized from 0 to 1.
ctrl.irdet.thresh_fl.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_THRESH_FL'),...
    'reply',{1,'single'},...
    varargin{:});                                                           
ctrl.irdet.thresh_fl.set = ...
    @(thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('POKE_THRESH_FL'),...
    'data',{thresh,'single'},...
    varargin{:});

%Request/set the current IR detector auto-threshold setting, in ADC ticks.
ctrl.irdet.thresh_adc.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_THRESH_ADC'),...
    'reply',{1,'uint16'},...
    varargin{:});                                                           
ctrl.irdet.thresh_adc.set = ...
    @(thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('POKE_THRESH_ADC'),...
    'data',{thresh,'uint16'},...
    varargin{:});

%Request/set the current IR detector auto-thresholding setting (0 = fixed, 1 = autoset).
ctrl.irdet.auto_thresh.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_THRESH_AUTO'),...
    'reply',{1,'uint8'},...
    varargin{:});                                                           
ctrl.irdet.auto_thresh.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('POKE_THRESH_AUTO'),...
    'data',{i,'uint8'},...
    varargin{:});

% Request/set the minimum signal range for positive detection with the 
% current nosepoke.
ctrl.irdet.min_range.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_POKE_MIN_RANGE'),...
    'reply',{1, 'uint8'; 1,'uint16'},...
    varargin{:});                                                           
ctrl.irdet.min_range.set = ...
    @(min_range,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('POKE_MIN_RANGE'),...
    'data',{min_range,'uint16'},...
    varargin{:});

% Request/set the current nosepoke sensor low-pass filter cutoff frequency, in Hz.
ctrl.irdet.filter.cutoff.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_POKE_LOWPASS_CUTOFF'),...
    'reply',{1, 'uint8'; 1,'single'},...
    varargin{:});             
ctrl.irdet.filter.cutoff.set = ...
    @(freq,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('POKE_LOWPASS_CUTOFF'),...
    'data',{freq,'single'},...
    varargin{:});

%Request the current IR detector status bitmask.
ctrl.irdet.reset = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('POKE_RESET'),....
    varargin{:});           


%% ************************************************************************
function ctrl = Vulintus_OTSC_Loadcell_Functions(ctrl, varargin)

% Vulintus_OTSC_Loadcell_Functions.m
% 
%   copyright 2024, Vulintus, Inc.
% 
%   VULINTUS_OTSC_LOADCELL_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have loadcells (i.e. force sensors).
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
% 
%   UPDATE LOG:
%   2024-10-30 - Drew Sloan - Script first created.
% 


% List the Vulintus devices that have loadcell/force sensor functions.
device_list = {'MT-IP','ST-AP','ST-VT'};

% If an cell arracy of connected devices was provided, match against the 
% device list.
if nargin >= 2
    connected_devices = varargin{1};                                        % Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     % Look for any matches between the two device lists.
    if ~any(i)                                                              % If no match was found...
        if isfield(ctrl,'loadcell')                                         % If there's a "loadcell" field in the control structure...
            ctrl = rmfield(ctrl,'loadcell');                                % Remove it.
        end
        return                                                              % Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          % Grab the handle for the serial connection.

% Loadcell/force sensor status functions.
ctrl.loadcell = [];                                                         % Create a field to hold loadcell/force sensor functions.

% Request/set the current loadcell/force sensor index.
ctrl.loadcell.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_LOADCELL_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.loadcell.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

% Request the current force/loadcell value, in grams, decigrams, or ADC 
% ticks.
ctrl.loadcell.read.grams = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_VAL_GM'),...
    'reply',{1,'uint32'; 1,'uint8'; 1,'single'},...
    varargin{:});         
ctrl.loadcell.read.decigrams = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_VAL_DGM'),...
    'reply',{1,'uint32'; 1,'uint8'; 1,'int16'},...
    varargin{:});
ctrl.loadcell.read.adc = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_VAL_ADC'),...
    'reply',{1,'uint32'; 1,'uint8'; 1,'uint16'},...
    varargin{:});  


% Request/set the current loadcell/force calibration baseline, in ADC ticks 
% (float).
ctrl.loadcell.calibration.baseline.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_CAL_BASELINE'),...
    'reply',{1,'single'},...
    varargin{:});    
ctrl.loadcell.calibration.baseline.set = ...
    @(baseline,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_CAL_BASELINE'),...
    'data',{baseline,'single'},...
    varargin{:});

% Measure the current loadcell/force sensor baseline (loadcell should be 
% unloaded).
ctrl.loadcell.calibration.baseline.measure = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_BASELINE_MEASURE'),...
    varargin{:});   

% Request/set the current loadcell/force calibration slope, in grams per 
% ADC tick (float).
ctrl.loadcell.calibration.slope.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_CAL_SLOPE'),...
    'reply',{1,'single'},...
    varargin{:});    
ctrl.loadcell.calibration.slope.set = ...
    @(slope,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_CAL_SLOPE'),...
    'data',{slope,'single'},...
    varargin{:});

% Measure the current loadcell/force sensor calibration slope given the
% specified force/weight.
ctrl.loadcell.calibration.slope.measure = ...
    @(weight,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_CAL_SLOPE_MEASURE'),...
    'data',{weight,'single'},...
    varargin{:});

% Request/set the current loadcell/force baseline-adjusting digital 
% potentiometer setting, scaled 0-1 (float).
ctrl.loadcell.pot.baseline.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_DIGPOT_BASELINE'),...
    'reply',{1,'single'},...
    varargin{:});    
ctrl.loadcell.pot.baseline.set = ...
    @(scaled_resistance,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_DIGPOT_BASELINE'),...
    'data',{scaled_resistance,'single'},...
    varargin{:});

% Adjust the current loadcell/force baseline-adjusting digital 
% potentiometer to be as close as possible to the specified ADC target 
% (loadcell should be unloaded).
ctrl.loadcell.pot.baseline.adjust = ...
    @(adc_target,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_BASELINE_ADJUST'),...
    'data',{adc_target,'uint16'},...
    varargin{:});

% Request/set the current force/loadcell gain setting (float).
ctrl.loadcell.gain.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_LOADCELL_GAIN'),...
    'reply',{1,'single'},...
    varargin{:});    
ctrl.loadcell.gain.set = ...
    @(gain,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('LOADCELL_GAIN'),...
    'data',{gain,'single'},...
    varargin{:});


%% ************************************************************************
function lookup_match = Vulintus_OTSC_Lookup_Match_Request(serialcon, req_code, report_code, lookup_table, req, varargin)

% Vulintus_OTSC_Lookup_Match_Request.m
%
%   copyright 2024, Vulintus, Inc.
%
%   VULINTUS_OTSC_LOOKUP_MATCH_REQUEST sends an OTSC request ("req_code"),
%   verifies that the response code ("report_code") matches the specified
%   expected value, and then matches the response, with specified data type 
%   ("reply_type"), to the specified lookup table ("lookup_table").
%
%   UPDATE LOG:
%   2024-11-21 - Drew Sloan - Function first created to make a general
%                             function for various mode settings.
%   2025-02-21 - Drew Sloan - Updated the requested reply specification to
%                             allow for a preceding index.
%


lookup_match = [];                                                          %Return empty brackets if no appropriate reply is received.
if isempty(varargin)                                                        %If there's no optional input arguments...
    [data, code] = Vulintus_OTSC_Transaction(serialcon, req_code,...
        'reply', req);                                                      %Request the current vibration task mode without optional input arguments.
else                                                                        %Otherwise...
    [data, code] = Vulintus_OTSC_Transaction(serialcon, req_code,...
        'reply', req,...
        varargin{:});                                                       %Request the current vibration task mode with optional input arguments.
end
if length(data) < size(req,1) || isempty(code) || code ~= report_code       %If no mode was returned...
    warning(['%s: There was no appropriate serial response to the '...
        'lookup match request!'], upper(mfilename));                        %Show a warning.
    return                                                                  %Skip the rest of the function.
end
if ~any(data(end) == vertcat(lookup_table{:,2}))                            %If none of the lookup entries matched the response...
    warning('%s: Lookup match request returned an unrecognized value!',...
        upper(mfilename));                                                  %Show a warning.
    lookup_match = sprintf('UNKNOWN_MODE_%1.0f',data(end));                 %Return the unknown value.
else
    lookup_match = ...
        lookup_table{data(end) == vertcat(lookup_table{:,2}),1};            %Return the recognized lookup entry.
end


%% ************************************************************************
function Vulintus_OTSC_Lookup_Match_Set(serialcon, set_code, lookup_table, lookup_val, data, varargin)

% Vulintus_OTSC_Lookup_Match_Set.m
%
%   copyright 2024, Vulintus, Inc.
%
%   VULINTUS_OTSC_LOOKUP_MATCH_SET matches a specified lookup value
%   ("lookup_val") to the specified lookup table ("lookup_table") and then
%   sends the match as a specified data type ("data_type") following the 
%   specified OTSC command ("set_code").
%
%   UPDATE LOG:
%   2024-11-21 - Drew Sloan - Function first created to make a general
%                             function for various mode settings.
%   2025-03-07 - Drew Sloan - Added functionality for passing more complex
%                             data blocks.
%


match_val = lookup_table{strcmpi(lookup_val,lookup_table(:,1)),2};          %Find the matching value for the specified value.
if isempty(match_val)                                                       %If no matching value was found...
     warning(['%s: "%s" does not match any recognized lookup table '...
         'entry!'], upper(mfilename), lookup_val);                          %Show a warning.
    return                                                                  %Skip the rest of the function.
end
data{1,1} = match_val;                                                      %Assume the match value goes in the first element of the data cell array.
if isempty(varargin)                                                        %If there's no optional input arguments...
    Vulintus_OTSC_Transaction(serialcon, set_code,...
        'data',data);                                                       %Send the match without optional input arguments.
else                                                                        %Otherwise...
    Vulintus_OTSC_Transaction(serialcon, set_code,...
        'data',data,...
        varargin{:});                                                       %Send the match with optional input arguments.
end


%% ************************************************************************
function ctrl = Vulintus_OTSC_Memory_Functions(ctrl, varargin)

%Vulintus_OTSC_Memory_Functions.m - Vulintus, Inc., 2022
%
%   VULINTUS_OTSC_MEMORY_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have non-volatile memory.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2023-10-02 - Drew Sloan - Function first created, split off from
%                             "Vulintus_OTSC_Common_Functions.m".
%   2023-12-07 - Drew Sloan - Updated calls to "Vulintus_Serial_Request" to
%                             allow multi-type responses.
%   2023-01-30 - Drew Sloan - Renamed function from
%                             "Vulintus_OTSC_EEPROM_Functions.m" to
%                             "Vulintus_OTSC_Memory_Functions.m".
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = { 'OT-3P',...
                'OT-CC'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'nvm')                                              %If there's a "nvm" field in the control structure...
            ctrl = rmfield(ctrl,'nvm');                                     %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Non-volatile memory functions.
ctrl.nvm = [];                                                              %Create a field to hold non-volatile memory functions.

%Request the device's non-volatile memory size.
ctrl.nvm.get_size = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_NVM_SIZE'),... % Updated
    'reply',{1,'uint32'},...
    varargin{:});             

%Read/write bytes to non-volatile memory.
ctrl.nvm.read = ...
    @(addr,N,type)Vulintus_Serial_EEPROM_Read(serialcon,...
    ctrl.stream.otsc_codes('WRITE_TO_NVM'),addr,N,type); % Updated
ctrl.nvm.write = ...
    @(addr,data,type)Vulintus_Serial_EEPROM_Write(serialcon,...
    ctrl.stream.otsc_codes('WRITE_TO_NVM'),addr,data,type); % Updated


%% ************************************************************************
function ctrl = Vulintus_OTSC_Motor_Setup_Functions(ctrl, varargin)

%Vulintus_OTSC_Motor_Setup_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_OTSC_MOTOR_SETUP_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have motors with configurable control parameters
%   i.e. coil current, microstepping, etc.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-06-04 - Drew Sloan - Function first created.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = { 'MT-PP',...
                'OT-PD',...
                'ST-TC',...
                'ST-AP'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'motor')                                            %If there's a "motor" field in the control structure...
            ctrl = rmfield(ctrl,'motor');                                   %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Motor setup functions.
ctrl.motor = [];                                                            %Create a field to hold motor setup functions.

%Request/set the current motor current setting, in milliamps.
ctrl.motor.current.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MOTOR_CURRENT'),... 
    'reply',{1,'uint16'},...
    varargin{:});                                                           
ctrl.motor.current.set = ...
    @(current_in_mA,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MOTOR_CURRENT'),... 
    'data',{current_in_mA,'uint16'},...
    varargin{:});

%Request/set the maximum possible motor current setting, in milliamps.
ctrl.motor.current.max.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MAX_MOTOR_CURRENT'),... 
    'reply',{1,'uint16'},...
    varargin{:});                                                           
ctrl.motor.current.max.set = ...
    @(current_in_mA,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MAX_MOTOR_CURRENT'),... 
    'data',{current_in_mA,'uint16'},...
    varargin{:});

%List the Vulintus devices that use the DRV8434S stepper driver.
device_list = { 'MT-PP',...
                'OT-SC',...
                'PB-LA',...
                'PB-PD',...
                'ST-AP'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        return                                                              %Skip execution of the rest of the function.
    end
end

%Request/set the firmware-based stall detection setting, on or off.
ctrl.motor.stall.detection.firmware.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_FW_STALL_DETECTION'),... 
    'reply',{1,'uint8'},...
    varargin{:});                                                           
ctrl.motor.stall.detection.firmware.set = ...
    @(enable,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('FW_STALL_DETECTION'),... 
    'data',{enable,'uint8'},...
    varargin{:});

%Request/set the hardware-based stall detection setting, on or off.
ctrl.motor.stall.detection.hardware.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_HW_STALL_DETECTION'),... 
    'reply',{1,'uint8'},...
    varargin{:});                                                           
ctrl.motor.stall.detection.hardware.set = ...
    @(enable,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('HW_STALL_DETECTION'),... 
    'data',{enable,'uint8'},...
    varargin{:});

%Request/set the current motor stall threshold, 0-4095.
ctrl.motor.stall.thresh.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_STALL_THRESH'),... 
    'reply',{1,'uint16'},...
    varargin{:});                                                           
ctrl.motor.stall.thresh.set = ...
    @(stall_thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('STALL_THRESH'),... 
    'data',{stall_thresh,'uint16'},...
    varargin{:});

%Request/set the current torque count scaling factor.
ctrl.motor.stall.trq_scaling.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TRQ_SCALING'),... 
    'reply',{1,'uint8'},...
    varargin{:});                                                           
ctrl.motor.stall.trq_scaling.set = ...
    @(torque_scale,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TRQ_SCALING'),... 
    'data',{torque_scale,'uint8'},...
    varargin{:});

%Request the current torque count, 0-4095.
ctrl.motor.trq_count = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TRQ_COUNT'),... 
    'reply',{1,'uint16'},...
    varargin{:});            

%Request/set the current number of steps to ignore before monitoring for stalls.
ctrl.motor.stall.ignore_steps.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TRQ_STALL_IGNORE'),... 
    'reply',{1,'uint16'},...
    varargin{:});                                                           
ctrl.motor.stall.ignore_steps.set = ...
    @(num_steps,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TRQ_STALL_IGNORE'),... 
    'data',{num_steps,'uint16'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_OTMP_Monitoring_Functions(ctrl, varargin)

%Vulintus_OTSC_OTMP_Monitoring_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_OTSC_OTMP_MONITORING_FUNCTIONS defines and adds OmniTrak 
%   Serial Communication (OTSC) functions to the control structure for 
%   Vulintus OmniTrak devices which have downstream-facing OmniTrak Module 
%   Port (OTMP) connections. As of June 2024, this only applies to the
%   OmniTrak Common Controller (OT-CC).
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-06-06 - Drew Sloan - Function first created.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = {'OT-CC'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'otmp')                                             %If there's a "otmp" field in the control structure...
            ctrl = rmfield(ctrl,'otmp');                                    %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%OmniTrak Module Port (OTMP) monitoring functions.
ctrl.otmp = [];

% Request the OmniTrak Module Port (OTMP) output current for the specified 
% port.
ctrl.otmp.iout = ...
    @(otmp_index, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OTMP_IOUT'),... 
    'data', {otmp_index,'uint8'},...
    'reply', {1,'uint8'; 1,'single'},...
    varargin{:});                                                           

% Request a bitmask indicating which OmniTrak Module Ports (OTMPs) are 
% active based on current draw.
ctrl.otmp.active = ...
    @(varargin)Vulintus_OTSC_OTMP_Monitoring_Ports_Bitmask(serialcon,...
    ctrl.stream.otsc_codes('REQ_OTMP_ACTIVE_PORTS'),... 
    varargin{:});    

% Request/set the specified OmniTrak Module Port (OTMP) high voltage supply 
% setting (0 = off <default>, 1 = high voltage).
ctrl.otmp.high_volt.get = ...
    @(otmp_index, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OTMP_HIGH_VOLT'),... 
    'data', {otmp_index,'uint8'},...
    'reply', {2,'uint8'},...
    varargin{:});
ctrl.otmp.high_volt.set = ...
    @(otmp_index,enable,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OTMP_HIGH_VOLT'),... 
    'data', {otmp_index,'uint8'; enable, 'uint8'},...
    varargin{:});

% Request a bitmask indicating which OmniTrak Module Ports (OTMPs) are in 
% overcurrent shutdown.
ctrl.otmp.overcurrent = ...
    @(varargin)Vulintus_OTSC_OTMP_Monitoring_Ports_Bitmask(serialcon,...
        ctrl.stream.otsc_codes('REQ_OTMP_OVERCURRENT_PORTS'),... 
        varargin{:});    

% Send a reset pulse to the specified OmniTrak module port's latched 
% overcurrent comparator.
ctrl.otmp.reset = ...
    @(otmp_index,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OTMP_ALERT_RESET'),... 
    'data', {otmp_index,'uint8'},...
    varargin{:});

% Request/set the serial "chunk" size required for transmission from the 
% specified OmniTrak Module Port (OTMP), in bytes.
ctrl.otmp.chunk.size.get = ...
    @(otmp_index, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OTMP_CHUNK_SIZE'),...
    'data', {otmp_index, 'uint8'},...
    'reply', {2, 'uint8'},...
    varargin{:});
ctrl.otmp.chunk.size.set = ...
    @(otmp_index,n_bytes,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OTMP_CHUNK_SIZE'),... 
    'data', {otmp_index, 'uint8'; n_bytes, 'uint8'},...
    varargin{:});

% Request/set the serial "chunk" timeout for the specified OmniTrak Module 
% Port (OTMP), in microseconds.
ctrl.otmp.chunk.timeout.get = ...
    @(otmp_index, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OTMP_PASSTHRU_TIMEOUT'),...
    'data', {otmp_index, 'uint8'},...
    'reply', {1, 'uint8'; 1, 'uint16'},...
    varargin{:});
ctrl.otmp.chunk.timeout.set = ...
    @(otmp_index, micros, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OTMP_PASSTHRU_TIMEOUT'),... 
    'data', {otmp_index, 'uint8'; micros, 'uint16'},...
    varargin{:});

% Reset the serial "chunk" size and "chunk" timeout to the defaults for all 
% OmniTrak Module Ports (OTMPs).
ctrl.otmp.chunk.reset = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OTMP_RESET_CHUNKING'),... 
    varargin{:});

%**************************************************************************

% Request the OmniTrak Module Port (OTMP) output current for the specified 
% port.
function active_ports = Vulintus_OTSC_OTMP_Monitoring_Ports_Bitmask(serialcon,code,varargin)
otmp_bitmask = Vulintus_OTSC_Transaction(serialcon,...
    code,...
    'reply', {2,'uint8'},...
    varargin{:});
active_ports = bitget(otmp_bitmask(2),1:otmp_bitmask(1));


%% ************************************************************************
function ctrl = Vulintus_OTSC_Optical_Flow_Functions(ctrl, varargin)

% Vulintus_OTSC_Optical_Flow_Functions.m
% 
%   copyright 2024, Vulintus, Inc.
% 
%   VULINTUS_OTSC_OPTICAL_FLOW_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have optical flow sensors (i.e. computer mouse
%   sensors).
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
% 
%   UPDATE LOG:
%   2025-01-27 - Drew Sloan - Script first created.
% 


% List the Vulintus devices that have optical flow sensor functions.
device_list = {'MT-ST'};

% If an cell arracy of connected devices was provided, match against the 
% device list.
if nargin >= 2
    connected_devices = varargin{1};                                        % Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     % Look for any matches between the two device lists.
    if ~any(i)                                                              % If no match was found...
        if isfield(ctrl,'optiflow')                                         % If there's a "optiflow" field in the control structure...
            ctrl = rmfield(ctrl,'optiflow');                                % Remove it.
        end
        return                                                              % Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          % Grab the handle for the serial connection.

% Optical flow sensor status functions.
ctrl.optiflow = [];                                                         % Create a field to hold optical flow sensor functions.

% Request/set the current optical flow sensor index.
ctrl.optiflow.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OPTICAL_FLOW_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.optiflow.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OPTICAL_FLOW_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

% Request the current x- and y-coordinates from the currently-selected 
% optical flow sensor, as 32-bit integers.
ctrl.optiflow.read.abs_xy = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OPTICAL_FLOW_XY'),...
    'reply',{1,'uint32'; 1,'uint8'; 2,'int32'},...
    varargin{:});         

% Request the current change in x- and y-coordinates from the 
% currently-selected optical flow sensor, as 32-bit integers.
ctrl.optiflow.read.delta_xy = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OPTICAL_FLOW_DELTA_XY'),...
    'reply',{1,'uint32'; 1,'uint8'; 2,'int32'},...
    varargin{:});

% Request the current change in value from the three selected optical flow
% vectors, as 16-bit integers.
ctrl.optiflow.read.delta_3vec = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_OPTICAL_FLOW_DELTA_3VEC'),...
    'reply',{1,'uint32'; 3,'int16'},...
    varargin{:});         

% Reset the current x- and y-coordinates and apparent animal orientation
% for all optical flow sensors on the module.
ctrl.optiflow.reset = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('OPTICAL_FLOW_RESET'),...
    varargin{:});


%% ************************************************************************
function Vulintus_OTSC_Process_Unknown_Block_Error(ctrl, src, varargin)

%
% Vulintus_OTSC_Process_Unknown_Block_Error.m
%
%   copyright 2025, Vulintus, Inc.
%
%   VULINTUS_OTSC_PROCESS_UNKNOWN_BLOCK_ERROR creates a warning message for
%   "UNKNOWN_BLOCK_ERROR" data blocks received through the Vulintus
%   OmniTrak Serial Communication (OTSC) protocol.
%   
%   UPDATE LOG:
%   2025-06-04 - Drew Sloan - Function first created.
%

fprintf('UNKNOWN_BLOCK_ERROR packet received from device #%1.0f',...
    src);                                                                   %Print a warning header.
if src == 0                                                                 %If the packet came from the primary device..
    if isnt_empty_field(ctrl,'device','sku')                                %If  the SKU is known...
        fprintf(1,' (%s)', ctrl.device.sku);                                %Print the SKU.
    end
else                                                                        %If the packet came from a module.
    if isnt_empty_field(ctrl,'otmp')                                        %If the module sku is known...
        error('NEED TO FINISH CODING THIS BIT!');
    end
end
fprintf(1,' -> 0x%04X\n', varargin{1});                                     %Print the hex value of the received packet code.


%% ************************************************************************
function ctrl = Vulintus_OTSC_Stepper_Motion_Functions(ctrl, varargin)

%Vulintus_OTSC_Stepper_Motion_Functions.m - Vulintus, Inc., 2023
%
%   Vulintus_OTSC_Stepper_Motion_Functions defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have linear motion capabilities, i.e. stepper 
%   motors and actuators.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-02-02 - Drew Sloan - Function first created.
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2024-06-04 - Drew Sloan - Renamed script from
%                             "Vulintus_OTSC_Movement_Functions.m" to
%                             "Vulintus_OTSC_Linear_Motion_Functions.m".
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%   2025-01-24 - Drew Sloan - Renamed script from
%                             "Vulintus_OTSC_Linear_Motion_Functions.m" to 
%                             "Vulintus_OTSC_Stepper_Motion_Functions.m".
%


%List the Vulintus devices that use these functions.
device_list = { 'MT-PP',...     % MotoTrak Pellet Pedestal Module
                'OT-PD',...     % OmniTrak Pocket Door Module
                'OT-SC',...     % OmniTrak Social Choice Module
                'PB-LA',...     % VPB Linear Autopositioner
                'PB-PD',...     % VPB Pellet Dispenser
                'ST-AP',...     % SensiTrak Arm Proprioception Module
              };

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'move')                                             %If there's a "move" field in the control structure...
            ctrl = rmfield(ctrl,'move');                                    %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.get_

%Module linear motion functions.
ctrl.move = [];                                                             %Create a field to hold linear motion functions.

%Initiate the homing routine on the module. 
ctrl.move.rehome = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MODULE_REHOME'),...
    varargin{:});                                  

%Retract the module movement to its starting or base position. 
ctrl.move.retract = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MODULE_RETRACT'),...
    varargin{:});                                 

%Request the current position of the module movement, in millimeters.
ctrl.move.position.current = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_CUR_POS_UNITS'),...
    'reply',{1,'single'},...
    varargin{:});                                                           

%Request/set the current target position of a module movement, in millimeters.
ctrl.move.position.target.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TARGET_POS_UNITS'),... 
    'reply',{1,'single'},...
    varargin{:});                                                           
ctrl.move.position.target.set = ...
    @(target_in_mm,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TARGET_POS_UNITS'),... 
    'data',{target_in_mm,'single'},...
    varargin{:});

%Request/set the current minimum position of a module movement, in millimeters.
ctrl.move.position.min.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MIN_POS_UNITS'),... 
    'reply',{1,'single'},...
    varargin{:});                                                           
ctrl.move.position.min.set = ...
    @(pos_in_mm,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MIN_POS_UNITS'),... 
    'data',{pos_in_mm,'single'},...
    varargin{:});

%Request/set the current maximum position of a module movement, in millimeters.
ctrl.move.position.max.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MAX_POS_UNITS'),... 
    'reply',{1,'single'},...
    varargin{:});      
ctrl.move.position.max.set = ...
    @(pos_in_mm,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MAX_POS_UNITS'),... 
    'data',{pos_in_mm,'single'},...
    varargin{:});

%Request/set the current minimum speed, in millimeters/second.
ctrl.move.speed.min.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MIN_SPEED_UNITS_S'),... 
    'reply',{1,'single'},...
    varargin{:});                                                           
ctrl.move.speed.min.set = ...
    @(speed_in_mmps,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MIN_SPEED_UNITS_S'),... 
    'data',{speed_in_mmps,'single'},...
    varargin{:});

%Request/set the current maximum speed, in millimeters/second.
ctrl.move.speed.max.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MAX_SPEED_UNITS_S'),... 
    'reply',{1,'single'},...
    varargin{:});   
ctrl.move.speed.max.set = ...
    @(speed_in_mmps,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('MAX_SPEED_UNITS_S'),... 
    'data',{speed_in_mmps,'single'},...
    varargin{:});

%Request/set the current movement acceleration, in millimeters/second^2.
ctrl.move.acceleration.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_ACCEL_UNITS_S2'),... 
    'reply',{1,'single'},...
    varargin{:});
ctrl.move.acceleration.set = ...
    @(accel_in_mmps2,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('ACCEL_UNITS_S2'),... 
    'data',{accel_in_mmps2,'single'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_TTL_IO_Functions(ctrl, varargin)

% Vulintus_OTSC_Haptic_Driver_Functions.m
% 
%   copyright 2024, Vulintus, Inc.
%
%   VULINTUS_OTSC_TTL_IO_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have TTL I/O connections (typically through BNC 
%   type connectors.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-11-21 - Drew Sloan - Function first created.
%


%List the Vulintus devices that have TTL I/O driver functions.
device_list = {'OT-CC'};

%If an cell arracy of connected devices was provided, match against the device list.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'ttl')                                              %If there's a "ttl" field in the control structure...
            ctrl = rmfield(ctrl,'ttl');                                     %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%TTL I/O status functions.
ctrl.ttl = [];                                                              %Create a field to hold TTL I/O functions.

%Request/set the current TTL I/O index.
ctrl.ttl.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TTL_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});             
ctrl.ttl.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TTL_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Immediately start/stop a TTL pulse.
ctrl.ttl.start = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TTL_START_PULSE'),...
    'data',{i,'uint8'},...
    varargin{:});
ctrl.ttl.stop = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TTL_STOP_PULSE'),...
    'data',{i,'uint8'},...
    varargin{:});   

%Request/set the current TTL pulse duration, in milliseconds.
ctrl.ttl.pulse.dur.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	otsc_codes.REQ_TTL_PULSE_DUR,...
    'reply',{1,'uint16'},...
    varargin{:});    
ctrl.ttl.pulse.dur.set = ...
    @(dur,varargin)Vulintus_OTSC_Transaction(serialcon,...
    otsc_codes.TTL_PULSE_DUR,...
    'data',{dur,'uint16'},...
    varargin{:});

%Request/set the current TTL pulse "on" and "off" values, in volts.
ctrl.ttl.pulse.levels.get = ...
    @(varargin)Vulintus_OTSC_fcn_REQ_TTL_PULSE_VALS(serialcon,...
    otsc_codes.REQ_TTL_PULSE_VALS,...
    [otsc_codes.TTL_PULSE_OFF_VAL, otsc_codes.TTL_PULSE_ON_VAL],...
    varargin{:});
ctrl.ttl.pulse.levels.set = ...
    @(lohi_volts,varargin)Vulintus_OTSC_fcn_TTL_PULSE_x_VAL(serialcon,...
    [otsc_codes.TTL_PULSE_OFF_VAL, otsc_codes.TTL_PULSE_ON_VAL],...
    lohi_volts,...
    varargin{:});

%Request/set the current TTL I/O pseudo-interrupt threshold, in volts.
ctrl.ttl.xint.thresh.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	otsc_codes.REQ_TTL_XINT_THRESH,...
    'reply',{1,'single'},...
    varargin{:});    
ctrl.ttl.xint.thresh.set = ...
    @(thresh,varargin)Vulintus_OTSC_Transaction(serialcon,...
    otsc_codes.TTL_XINT_THRESH,...
    'data',{thresh,'single'},...
    varargin{:});

%Request/set the the current TTL I/O pseudo-interrupt mode.
xint_mode_lookup = {    'none',     0;
                        'rising',   1;
                        'falling',  2;
                        'change',   3;
                     };
ctrl.ttl.xint.mode.get = ...
    @(varargin)Vulintus_OTSC_Lookup_Match_Request(serialcon,...
    otsc_codes.REQ_TTL_XINT_MODE,...
    otsc_codes.TTL_XINT_MODE,...
    xint_mode_lookup,...
    'uint8',...
    varargin{:});
ctrl.ttl.xint.mode.set = ...
    @(mode,varargin)Vulintus_OTSC_Lookup_Match_Set(serialcon,...
    otsc_codes.TTL_XINT_MODE,...
    xint_mode_lookup,...
    mode,...
    {0, 'uint8'},...
    varargin{:});

%Set the specified TTL I/O's digital output value.
ctrl.ttl.digital.out = ...
    @(i,level,varargin)Vulintus_OTSC_Transaction(serialcon,...
    otsc_codes.TTL_SET_DOUT,...
    'data',{i,'uint8'; level,'uint8'},...
    varargin{:});

%Request the current TTL digital status bitmask.
ctrl.ttl.digital.bitmask = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    otsc_codes.REQ_TTL_DIGITAL_BITMASK,...
    'reply',{1, 'uint32'; 1,'uint8'},...
    varargin{:});

%Set the TTL analog output value.
ctrl.ttl.analog.out = ...
    @(i,volts,varargin)Vulintus_OTSC_Transaction(serialcon,...
    otsc_codes.TTL_SET_AOUT,...
    'data',{i,'uint8'; volts,'single'},...
    varargin{:});

%Request the specified TTL I/O's analog input value.
ctrl.ttl.analog.read = ...
    @(i, varargin)Vulintus_OTSC_Transaction(serialcon,...
    otsc_codes.REQ_TTL_AIN,...
    'data',{i,'uint8'},...
    'reply',{1,'uint8'; 1,'uint32'; 1,'single'},...
    varargin{:});


%Request the current TTL pulse "on" and "off" values.
function lohi_volts = Vulintus_OTSC_fcn_REQ_TTL_PULSE_VALS(serialcon, req_code, report_code, varargin)
lohi_volts = nan(1,2);                                                      %Return NaNs if no appropriate reply is received. 
if isempty(varargin)                                                        %If there's no optional input arguments...
    [data, code] = Vulintus_OTSC_Transaction(serialcon, req_code,...
        'reply',{1,'single'; 1, 'uint16'; 1, 'single'});                    %Request the TTL pulse "off"/"on" values without optional input arguments.
else                                                                        %Otherwise...
    [data, code] = Vulintus_OTSC_Transaction(serialcon, req_code,...
        'reply',{1,'single'; 1, 'uint16'; 1, 'single'},...
        varargin{:});                                                       %Request the TTL pulse "off"/"on" values with optional input arguments.
end
if isempty(data) || length(data) ~= 3 || isempty(code) || ...
        code ~= report_code(1) || data(2) ~= report_code(2)                 %If the TTL pulse levels weren't returned...
    warning(['%s: There was no response to the TTL I/O "off"/"on" '...
        'levels request!'], upper(mfilename));                              %Show a warning.
    return                                                                  %Skip the rest of the function.
end
lohi_volts = data([1,3]);                                                   %Return the "off"/"on" voltage values.


%Set the current TTL pulse "on" and "off" values.
function Vulintus_OTSC_fcn_TTL_PULSE_x_VAL(serialcon, set_code, lohi_volts, varargin)
if length(lohi_volts) ~= 2                                                  %If two values weren't specified...
     warning(['%s: %1.0f values specified for the TTL "off"/"on" '...
         'levels! Two (2) values should be specified!'],...
         upper(mfilename), length(lohi_volts));                             %Show a warning.
    return                                                                  %Skip the rest of the function.
end
if isempty(varargin)                                                        %If there's no optional input arguments...
    Vulintus_OTSC_Transaction(serialcon, set_code(1),...
        'data',{lohi_volts(1),'single'});                                   %Set the "off" level without optional input arguments.
    Vulintus_OTSC_Transaction(serialcon, set_code(2),...
        'data',{lohi_volts(2),'single'});                                   %Set the "on" level without optional input arguments.
else                                                                        %Otherwise...
    Vulintus_OTSC_Transaction(serialcon, set_code(1),...
        'data',{lohi_volts(1),'single'},...
        varargin{:});                                                       %Set the "off" level optional input arguments.
    Vulintus_OTSC_Transaction(serialcon, set_code(2),...
        'data',{lohi_volts(2),'single'},...
        varargin{:});                                                       %Set the "on" level optional input arguments.
end


%% ************************************************************************
function ctrl = Vulintus_OTSC_Thermal_Image_Functions(ctrl, varargin)

%Vulintus_OTSC_Thermal_Image_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_OTSC_THERMAL_IMAGE_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have thermal imaging sensors.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2023-10-02 - Drew Sloan - Function first created.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = {'HT-TH'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'therm_im')                                         %If there's a "therm_im" field in the control structure...
            ctrl = rmfield(ctrl,'therm_im');                                %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Thermal imaging functions.
ctrl.therm_im = [];                                                         %Create a field to hold thermal imaging functions.

%Request the current thermal hotspot x-y position, in units of pixels.
ctrl.therm_im.hot_pix = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_THERM_XY_PIX'),...
    'reply',{1, 'uint32'; 3,'uint8'; 1,'single'},...
    varargin{:});                                                           

%Request a thermal pixel image as 16-bit unsigned integers in units of deciKelvin (dK, or Kelvin * 10).
ctrl.therm_im.pixels_dk = @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_THERM_PIXELS_INT_K'),...
    'reply',{1, 'uint32', 3,'uint8'; 1024,'uint16'},...
    varargin{:});                                               

%Request a thermal pixel image as a fixed-point 6/2 type (6 bits for the unsigned integer part, 2 bits for the decimal part), in units of Celcius.
ctrl.therm_im.pixels_fp62 = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
	ctrl.stream.otsc_codes('REQ_THERM_PIXELS_FP62'),...
    'reply',{1, 'uint32'; 1027,'uint8'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_Tone_Functions(ctrl, varargin)

%Vulintus_OTSC_Tone_Functions.m - Vulintus, Inc., 2023
%
%   VULINTUS_OTSC_TONE_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices which have tone-playing capabilities.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2023-09-28 - Drew Sloan - Function first created, split off from
%                             "Vulintus_OTSC_Common_Functions.m".
%   2023-12-07 - Drew Sloan - Updated calls to "Vulintus_Serial_Request" to
%                             allow multi-type responses.
%   2024-01-31 - Drew Sloan - Added optional input arguments for
%                             passthrough commands.
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = { 'MT-PP',...
                'OT-3P',...
                'OT-CC',...
                'OT-NP',...
                'OT-PR',...
                'OT-LR',...
                'ST-AP',...
                'ST-VT'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'tone')                                             %If there's a "tone" field in the control structure...
            ctrl = rmfield(ctrl,'tone');                                    %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Tone functions.
ctrl.tone = [];                                                             %Create a subfield to hold tone functions.

%Play the specified tone.
ctrl.tone.on = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('PLAY_TONE'),...
    'data',{i,'uint8'},...
    varargin{:});                            

%Stop any currently-playing tone.
ctrl.tone.off = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('STOP_TONE'),...
    varargin{:});                                      

%Request/set the current tone index.
ctrl.tone.index.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TONE_INDEX'),...
    'reply',{1,'uint8'},...
    varargin{:});     
ctrl.tone.index.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TONE_INDEX'),...
    'data',{i,'uint8'},...
    varargin{:});

%Request/set the current tone frequency.
ctrl.tone.freq.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TONE_FREQ'),... 
    'reply',{1,'uint16'},...
    varargin{:});       
ctrl.tone.freq.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TONE_FREQ'),... 
    'data',{i,'uint16'},...
    varargin{:});

%Request/set the current tone duration.
ctrl.tone.dur.get = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TONE_DUR'),... 
    'reply',{1,'uint16'},...
    varargin{:});         
ctrl.tone.dur.set = ...
    @(i,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TONE_DUR'),... 
    'data',{i,'uint16'},...
    varargin{:});

%Request/set the tone volume, normalized from 0 to 1.
ctrl.tone.volume.get =  ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_TONE_VOLUME'),... 
    'reply',{1,'single'},...
    varargin{:});  
ctrl.tone.volume.set = ...
    @(volume,varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('TONE_VOLUME'),... 
    'data',{volume,'single'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_VPB_Monitoring_Functions(ctrl, varargin)

%Vulintus_OTSC_VPB_Monitoring_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_OTSC_VPB_MONITORING_FUNCTIONS defines and adds OmniTrak 
%   Serial Communication (OTSC) functions to the control structure for 
%   Vulintus OmniTrak devices which have Vulintus Peripheral Bus (VPB)
%   connections.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-07-11 - Drew Sloan - Function first created.
%


%List the Vulintus devices that use these functions.
device_list = {'OT-CC'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'vpb')                                             %If there's a "vpb" field in the control structure...
            ctrl = rmfield(ctrl,'vpb');                                    %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Vulintus Peripheral Bus (VPB) monitoring functions.
ctrl.vpb = [];

%Request/set the specified OmniTrak Module Port (OTMP) high voltage supply setting (0 = off <default>, 1 = high voltage
ctrl.vpb.ap_dist_x.set = ...
    @(dist, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('AP_DIST_X'),...
    'data',{dist,'single'},...
    varargin{:});

ctrl.vpb.ap_offset.set = ...
    @(dist, varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('AP_DIST_X'),...
    'data',{dist + 102.4,'single'},...
    varargin{:});


%% ************************************************************************
function ctrl = Vulintus_OTSC_WiFi_Functions(ctrl, varargin)

%Vulintus_OTSC_WiFi_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_OTSC_WIFI_FUNCTIONS defines and adds OmniTrak Serial
%   Communication (OTSC) functions to the control structure for Vulintus
%   OmniTrak devices with integrated WiFi modules.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-01-30 - Drew Sloan - Function first created, split off from
%                             "Vulintus_OTSC_Common_Functions.m".
%   2024-02-22 - Drew Sloan - Organized functions by scope into subfields.
%   2024-06-07 - Drew Sloan - Added a optional "devices" input argument to
%                             selectively add the functions to the control 
%                             structure.
%


%List the Vulintus devices that use these functions.
device_list = { 'HT-TH',...
                'OT-CC'};

%If an cell arracy of connected devices was provided, match against the device lis.
if nargin >= 2
    connected_devices = varargin{1};                                        %Grab the list of connected devices.
    [~,i,~] = intersect(connected_devices,device_list);                     %Look for any matches between the two device lists.
    if ~any(i)                                                              %If no match was found...
        if isfield(ctrl,'wifi')                                             %If there's a "wifi" field in the control structure...
            ctrl = rmfield(ctrl,'wifi');                                    %Remove it.
        end
        return                                                              %Skip execution of the rest of the function.
    end
end

serialcon = ctrl.stream.serialcon;                                          %Grab the handle for the serial connection.

%Controller status functions.
ctrl.wifi = [];                                                             %Create a field to hold WiFi functions.

%Request the device's MAC address.
ctrl.wifi.mac_addr = ...
    @(varargin)Vulintus_OTSC_Transaction(serialcon,...
    ctrl.stream.otsc_codes('REQ_MAC_ADDR'),...
    'reply',{1,'uint8'},...
    varargin{:});


%% ************************************************************************
function Vulintus_Serial_Close(serialcon, stream_disable_fcn, set_baudrate_fcn, flush_fcn)

% Vulintus_Serial_Close.m
%
%   copyright 2022, Vulintus, Inc.
%
%   VULINTUS_SERIAL_CLOSE closes the specified serial connection,
%   performing all necessary housekeeping functions and then deleting the
%   objects.
%
%   UPDATE LOG:
%   2022-02-25 - Drew Sloan - Function first created.
%   2024-11-11 - Drew Sloan - Switched out input variables for function
%                             handles with captured variables to simplify 
%                             function updates going forward..
%


stream_disable_fcn();                                                       %Disable streaming on the device.
new_baudrate = set_baudrate_fcn();                                          %Reset the baudrate to the default.
if isempty(new_baudrate)                                                    %If no confirmation was returned...
    cprintf('*r','ERROR IN %s: ', upper(mfilename));                        %Start an error message.
    cprintf('r',['Attempt to set the serial baud rate back to the '...
        'default value failed! \n\tNo confirmation packet received '...
        'from the device.\n']);                                             %Show an error.
else                                                                        %Otherwise...
    fprintf(1,['%s: Serial baud rate reset back to default value '...
        '%1.0f Hz.\n'],upper(mfilename), new_baudrate);                     %Show an error.
end
pause(0.01);                                                                %Pause for 10 milliseconds.
drawnow;                                                                    %Flush the event queue.
flush_fcn();                                                                %Clear the input buffers.
delete(serialcon);                                                          %Delete the serial object.


%% ************************************************************************
function comm_check = Vulintus_Serial_Comm_Verification(serialcon,ver_cmd,ver_key,stream_cmd,varargin)

%Vulintus_Serial_Comm_Verification.m - Vulintus, Inc., 2022
%
%   VULINTUS_SERIAL_COMM_VERIFICATION sends the communication verification
%   code and the verification key to the device connected through the
%   specified serial object, and checks for a matching reply.
%
%   UPDATE LOG:
%   2022-02-25 - Drew Sloan - Function first created.
%   2024-06-06 - Drew Sloan - Added the option to use the older deprecated
%                             serial functions.
%


wait_for_reply = 1;                                                         %Wait for the reply by default.
msg_type = 'none';                                                          %Don't print waiting messages by default.
for i = 1:length(varargin)                                                  %Step through any optional input arguments.
    if ischar(varargin{i}) && strcmpi(varargin{i},'nowait')                 %If the user specified not to wait for the reply...
        wait_for_reply = 0;                                                 %Don't wait for the reply.
    elseif isstruct(varargin{i}) && strcmpi(varargin{i}.type,'big_waitbar') %If a big waitbar structure was passed...
        msg_handle = varargin{i};                                           %Set the message display handle to the structure.
        msg_type = 'big_waitbar';                                           %Set the message display type to "big_waitbar".
    elseif ishandle(varargin{i}) && isprop(varargin{i},'Type')              %If a graphics handles was passed.     
        msg_type = lower(varargin{i}.Type);                                 %Grab the object type.
        if strcmpi(varargin{i}.Type,'uicontrol')                            %If the object is a uicontrol...
            msg_type = lower(varargin{i}.Style);                            %Grab the uicontrol style.
        end
        msg_handle = varargin{i};                                           %Set the message display handle to the text object.
    end
end

comm_check = 0;                                                             %Assume the verification will fail by default.

vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);               %Load the basic serial functions for either "serialport" or "serial".

if vulintus_serial.bytes_available() > 0 && wait_for_reply                  %If there's any data on the serial line and we're waiting for a reply...
    Vulintus_OTSC_Transaction(serialcon,stream_cmd,'data',{0,'uint8'});     %Disable streaming on the device.
    timeout = datetime('now') + seconds(1);                                 %Set a time-out point for the following loop.
    while datetime('now') < timeout && ...
            vulintus_serial.bytes_available() > 0                           %Loop until all data is cleared off the serial line.        
        pause(0.05);                                                        %Pause for 50 milliseconds.
        vulintus_serial.flush();                                            %Flush any existing bytes off the serial line.
    end
end
vulintus_serial.write(ver_cmd,'uint16');                                    %Write the verification command.
    
if ~wait_for_reply                                                          %If we're not waiting for the reply.
    return                                                                  %Exit the function.
end

switch msg_type                                                             %Switch between the message display types.
    case 'text'                                                             %Text object on an axes.
        message = get(msg_handle,'string');                                 %Grab the current message in the text object.
        message(end+1) = '.';                                               %Add a period to the end of the message.
        set(msg_handle,'string',message);                                   %Update the message in the text label on the figure.
    case {'listbox','uitextarea'}                                           %UIControl messagebox.
        Append_Msg(msg_handle,'.');                                         %Add a period to the last message in the messagebox.
    case 'big_waitbar'                                                      %Vulintus' big waitbar.
        val = 1 - 0.9*(1 - msg_handle.value());                             %Calculate a new value for the waitbar.
        msg_handle.value(val);                                              %Update the waitbar value.
end

timeout_timer = tic;                                                        %Start a timeout timer.
while vulintus_serial.bytes_available() <= 2 && toc(timeout_timer) < 1.0    %Loop until a reply is received.
    pause(0.01);                                                            %Pause for 10 milliseconds.
end

if vulintus_serial.bytes_available() >= 2                                   %If there's at least 2 bytes on the serial line.
    ver_code = vulintus_serial.read(1,'uint16');                            %Read in 1 unsigned 16-bit integer.
    if ver_code == ver_key                                                  %If the value matches the verification code...
        comm_check = 1;                                                     %Set the OTSC communication flag to 1.
    end
end
vulintus_serial.flush();                                                    %Clear the input and output buffers.


%% ************************************************************************
function [reply, code] = Vulintus_Serial_EEPROM_Read(serialcon,cmd,addr,N,datatype)

%Vulintus_Serial_EEPROM_Read.m - Vulintus, Inc., 2022
%
%   VULINTUS_SERIAL_EEPROM_READ sends the EEPROM read request
%   command, followed by the target address and number of bytes to read.
%   The function will then read in the received bytes as the type specified
%   by the user.
%
%   UPDATE LOG:
%   2022-03-03 - Drew Sloan - Function first created, adapted from
%                             Vulintus_Serial_Request_uint32.m.
%   2024-06-06 - Drew Sloan - Added the option to use the older deprecated
%                             serial functions.
%

reply = [];                                                                 %Assume no reply values will be received by default.
code = 0;                                                                   %Assume no reply code will be received by default.

switch lower(datatype)                                                      %Switch between the available data types...
    case {'uint8','int8','char'}                                            %For 8-bit data types...
        bytes_per_val = 1;                                                  %The number of bytes is the size of the request.
    case {'uint16','int16'}                                                 %For 16-bit data types...
        bytes_per_val = 2;                                                  %The number of bytes is the 2x size of the request.
    case {'uint32','int32','single'}                                        %For 32-bit data types...
        bytes_per_val = 4;                                                  %The number of bytes is the 4x size of the request. 
    case {'double'}                                                         %For 64-bit data types...
        bytes_per_val = 8;                                                  %The number of bytes is the 8x size of the request.
end

vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);               %Load the basic serial functions for either "serialport" or "serial".

if vulintus_serial.bytes_available() > 0                                    %If there's currently any data on the serial line.
    vulintus_serial.flush();                                                %Flush any existing bytes off the serial line.
end
vulintus_serial.write(cmd,'uint16');                                        %Write the command.
vulintus_serial.write(addr,'uint32');                                       %Write the EEPROM address.
vulintus_serial.write(N*bytes_per_val,'uint8');                             %Write the number of bytes to read back.
vulintus_serial.write(0,'uint8');                                           %Write a dummy byte to drive the Serial read loop on the device.
    
timeout_timer = tic;                                                        %Start a time-out timer.
while toc(timeout_timer) < 1 && ...
        vulintus_serial.bytes_available() < (2 + N*bytes_per_val)           %Loop for 1 second or until the expected reply shows up on the serial line.
    pause(0.01);                                                            %Pause for 10 milliseconds.
end
if vulintus_serial.bytes_available() >= 2                                   %If a block code was returned...
    code = vulintus_serial.read(1,'uint16');                                %Read in the unsigned 16-bit integer block code.
else                                                                        %Otherwise...
    return                                                                  %Skip execution of the rest of the function
end
N = floor(vulintus_serial.bytes_available()/bytes_per_val);                 %Set the number of values to read.
if N > 0                                                                    %If there's any integers on the serial line...        
    reply = vulintus_serial.read(N,datatype);                               %Read in the requested values as the specified type.
    reply = double(reply);                                                  %Convert the output type to double to play nice with comparisons in MATLAB.
end
vulintus_serial.flush();                                                    %Flush any remaining bytes off the serial line.


%% ************************************************************************
function Vulintus_Serial_EEPROM_Write(serialcon,cmd,addr,data,type)

%Vulintus_Serial_EEPROM_Write.m - Vulintus, Inc., 2022
%
%   VULINTUS_SERIAL_EEPROM_WRITE sends via serial, in order, the 
%       1) OTMP command to write bytes to the EEPROM,
%       2) target EEPROM address, followed by the,
%       3) number of bytes to write, and
%       4) bytes of the specified data, broken down by data type.
%
%   UPDATE LOG:
%   2022-03-03 - Drew Sloan - Function first created, adapted from
%                             Vulintus_OTSC_Transaction_uint32.m.
%   2024-06-06 - Drew Sloan - Added the option to use the older deprecated
%                             serial functions.
%


vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);               %Load the basic serial functions for either "serialport" or "serial".

vulintus_serial.write(cmd,'uint16');                                        %Write the EEPROM write command.
vulintus_serial.write(addr,'uint32');                                       %Write the target EEPROM address.
if isempty(data)                                                            %If no data was sent...
    vulintus_serial.write(0,'uint8');                                       %Send a zero for the number of following bytes.
else                                                                        %Otherwise, if data is to be sent...
    switch lower(type)                                                      %Switch between the available data types...
        case {'uint8','int8','char'}                                        %For 8-bit data types...
            N = numel(data);                                                %The number of bytes is the size of the array.
        case {'uint16','int16'}                                             %For 16-bit data types...
            N = 2*numel(data);                                              %The number of bytes is the 2x size of the array.
        case {'uint32','int32','single'}                                    %For 32-bit data types...
            N = 4*numel(data);                                              %The number of bytes is the 4x size of the array. 
        case {'double'}                                                     %For 64-bit data types...
            N = 8*numel(data);                                              %The number of bytes is the 8x size of the array.
    end
    vulintus_serial.write(data,type);                                       %Send the data as the specified type.
end


%% ************************************************************************
function [ctrl, varargout] = Vulintus_Serial_Load_OTSC_Functions(ctrl, varargin)

%Vulintus_Serial_Load_OTSC_Functions.m - Vulintus, Inc., 2024
%
%   VULINTUS_SERIAL_LOAD_OTSC_FUNCTIONS adds OmniTrak Serial Communication 
%   (OTSC) functions to the control structure for Vulintus devices using
%   the OTSC protocol.
% 
%   NOTE: These functions are designed to be used with the "serialport" 
%   object introduced in MATLAB R2019b and will not work with the older 
%   "serial" object communication.
%
%   UPDATE LOG:
%   2024-06-06 - Drew Sloan - Function first created.
%   2024-10-22 - Drew Sloan - Added Haptic driver functions.
%   2025-04-10 - Drew Sloan - Converted the device list from a structure to
%                             a dictionary.
%

varargout{1} = {};                                                          %Assume we will return zero device SKUs.

device_list = Vulintus_Load_OTSC_Device_IDs;                                %Load the OTSC device list.
[device_id, code] = ctrl.device.id();                                       %Grab the OTSC device id.
if code ~= ctrl.stream.otsc_codes('DEVICE_ID') || ...
        ~isKey(device_list, device_id)                                      %If the return code was wrong or the device ID isn't recognized...
    ctrl.device.sku = [];                                                   %Set the device name to empty brackets in the structure.
else                                                                        %Otherwise, if the device was recognized...
    ctrl.device.sku = device_list(device_id).sku;                           %Save the device SKU (4-character product code) to the structure.
    ctrl.device.name = device_list(device_id).name;                         %Save the full device name to the structure.
end

sources = 0;                                                                %Assume by default that there is only the primary device as a source.

devices = {ctrl.device.sku};                                                %Put the primary device SKU into a cell array.
ctrl = Vulintus_OTSC_OTMP_Monitoring_Functions(ctrl, devices);              %OTMP-monitoring functions.
if isfield(ctrl,'otmp')                                                     %If this device has downstream-facing module ports...    
    active_ports = ctrl.otmp.active();                                      %Check which ports are active.    
    for i = 1:length(active_ports)                                          %Step through all of the ports.
        if active_ports(i)                                                  %If there's a device on this port.
            [device_id, code] = ctrl.device.id('passthrough',i);            %Grab the OTSC device id.            
            if isempty(device_id)                                           %If no code was returned.
                cprintf([1,0.5,0],['OmniTrak Module Port #%1.0f is '...
                    'drawing power, but not responding to OTSC '...
                    'communication!\n'],i);                                 %Indicate the port is not responding.
                ctrl.otmp.port(i).connected = -1;                           %Label the port as non-responding.
                ctrl.otmp.port(i).sku = [];                                 %Set the SKU field to empty.
            elseif code ~= ctrl.stream.otsc_codes('DEVICE_ID') || ...
                    ~isKey(device_list, device_id)                          %If the return code was wrong or the device ID isn't recognized...
                ctrl.otmp.port(i).sku = [];                                 %Set the device name to empty brackets in the structure.
            else                                                            %Otherwise, if the device was recognized...
                ctrl.otmp.port(i).sku = device_list(device_id).sku;         %Save the device SKU (4-character product code) to the structure.
                ctrl.otmp.port(i).name = device_list(device_id).name;       %Save the full device name to the structure.
            end
            ctrl.otmp.port(i).connected = 1;                                %Label the port as connected.
            sources(end+1,1) = i;                                           %Add the port index to the source list.
        else                                                                %Otherwise, if there's not device on this port.
            ctrl.otmp.port(i).connected = 0;                                %Label the port as disconnected
            ctrl.otmp.port(i).sku = [];                                     %Set the SKU field to empty.
        end
    end
    devices = horzcat(devices,{ctrl.otmp.port.sku});                        %Add the connected devices to the device SKU list.
    devices(cellfun(@isempty,devices)) = [];                                %Kick out the empty cells.
end

%Device-specific OTSC functions.
ctrl = Vulintus_OTSC_Cage_Light_Functions(ctrl, devices);                   %Overhead cage light functions.
ctrl = Vulintus_OTSC_Capacitive_Sensor_Functions(ctrl, devices);            %Capacitive sensor functions.
ctrl = Vulintus_OTSC_BLE_Functions(ctrl, devices);                          %Bluetooth Low Energy (BLE) functions.
ctrl = Vulintus_OTSC_Cue_Light_Functions(ctrl, devices);                    %Cue light functions.
ctrl = Vulintus_OTSC_Dispenser_Functions(ctrl, devices);                    %Pellet/liquid dispenser control functions.
ctrl = Vulintus_OTSC_Haptic_Driver_Functions(ctrl, devices);                %Haptic driver functions.
ctrl = Vulintus_OTSC_IR_Detector_Functions(ctrl, devices);                  %IR detector functions.
ctrl = Vulintus_OTSC_Stepper_Motion_Functions(ctrl, devices);               %Module linear motion functions.
ctrl = Vulintus_OTSC_Loadcell_Functions(ctrl, devices);                     %Loadcell/force sensor functions.
ctrl = Vulintus_OTSC_Memory_Functions(ctrl, devices);                       %Nonvolatile memory access functions.
ctrl = Vulintus_OTSC_Motor_Setup_Functions(ctrl, devices);                  %Motor setup functions.
ctrl = Vulintus_OTSC_Optical_Flow_Functions(ctrl, devices);                 %Optical flow sensor functions.
ctrl = Vulintus_OTSC_Thermal_Image_Functions(ctrl, devices);                %Thermal imaging functions.
ctrl = Vulintus_OTSC_Tone_Functions(ctrl, devices);                         %Tone-playing functions.  
ctrl = Vulintus_OTSC_TTL_IO_Functions(ctrl, devices);                       %TTL I/O functions.  
ctrl = Vulintus_OTSC_VPB_Monitoring_Functions(ctrl, devices);               %VPB-monitoring functions. 
ctrl = Vulintus_OTSC_WiFi_Functions(ctrl, devices);                         %WiFi functions.   

% ctrl = Vulintus_OTSC_STAP_Functions(ctrl, devices);             %STAP-specific functions.
% ctrl = Vulintus_OTSC_STTC_Functions(ctrl, devices);             %STTC-specific functions.

ctrl.stream.sources = sources;                                              %Update the sources list in the stream class.

varargout{1} = devices;                                                     %Return a list of the connected devices.


%% ************************************************************************
function [port_list, varargout] = Vulintus_Serial_Port_List(varargin)

%Vulintus_Serial_Port_List.m - Vulintus, Inc.
%
%   VULINTUS_SERIAL_PORT_LIST finds all connected serial port devices and
%   pairs the assigned COM port with device descriptions stored in the
%   system registry.
%
%   UPDATE LOG:
%   2021-11-29 - Drew Sloan - Function first created.
%   2024-02-27 - Drew Sloan - Branched the port matching file read
%                             functions into dedicated functions.
%   2024-06-06 - Drew Sloan - Added the option to use the older deprecated
%                             serial functions.
%

if datetime(version('-date')) > datetime('2019-09-17')                      %If the version is 2019b or newer...
    use_serialport = true;                                                  %Use the newer serialport functions by default.
else                                                                        %Otherwise...
    use_serialport = false;                                                 %Use the older serial functions by default.
end
if nargin > 0                                                               %If at least one input argument was included...
    use_serialport = varargin{1};                                           %Assume the serial function version setting was passed.
end

% List all active COM ports.
if use_serialport                                                           %If we're using the newer serialport functions...
    ports = serialportlist('all');                                          %Grab all serial ports.    
    available_ports = serialportlist('available');                          %Find all ports that are currently available.
else                                                                        %Otherwise, if we're using the older serial functions...
    ports = instrhwinfo('serial');                                          %Grab information about the available serial ports.
    available_ports = ports.AvailableSerialPorts;                           %Find all ports that are currently available.
    ports = ports.SerialPorts;                                              %Save the list of all serial ports regardless of whether they're busy.
end
port_list = struct;                                                         %Set the function output to an empty structure.
if isempty(ports)                                                           %If no serial ports were found...    
    return                                                                  %Skip execution of the rest of the function.
end

% Label ports as available or busy.
for i = 1:numel(ports)                                                      %Step through each port.
    port_list(i).com = ports{i};                                            %Populate the structure with the COM number.
    port_list(i).busy = ~any(strcmpi(port_list(i).com,available_ports));    %Flag if the port is busy.
    port_list(i).name = [];                                                 %Create an empty field for the name.
    port_list(i).alias = [];                                                %Create an empty field for the alias.
end

% Grab the VID, PID, and device description for all known USB devices.
key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\';              %Set the registry query field.
[~, txt] = dos(['REG QUERY ' key ' /s /f "FriendlyName" /t "REG_SZ"']);     %Query the registry for all USB devices.
txt = textscan(txt,'%s','delimiter','\t');                                  %Parse the text by row.
txt = cat(1,txt{:});                                                        %Reshape the cell array into a vertical array.
dev_info = struct(  'name',  [],...
                    'alias',        [],...
                    'port',         [],...
                    'vid',          [],...
                    'pid',          []);                                    %Create a structure to hold device information.
dev_i = 0;                                                                  %Create a device counter.
for i = 1:length(txt)                                                       %Step through each entry.
    if startsWith(txt{i},key)                                               %If the line starts with the key.
        dev_i = dev_i + 1;                                                  %Increment the device counter.
        if contains(txt{i},'VID_')                                          %If this line includes a VID.
            j = strfind(txt{i},'VID_');                                     %Find the device VID.
            dev_info(dev_i).vid = txt{i}(j+4:j+7);                          %Grab the VID.
        end
        if contains(txt{i},'PID_')                                          %If this line includes a PID.
            j = strfind(txt{i},'PID_');                                     %Find the device PID.
            dev_info(dev_i).pid = txt{i}(j+4:j+7);                          %Grab the PID.
        end
        if contains(txt{i+1},'REG_SZ')                                      %If this line includes a device name.
            j = strfind(txt{i+1},'REG_SZ');                                 %Find the REG_SZ preceding the name on the following line.
            dev_info(dev_i).name = strtrim(txt{i+1}(j+7:end));              %Grab the port name.
        end
    end
end
keepers = zeros(length(dev_info),1);                                        %Create a matrix to mark devices for exclusion.
for i = 1:length(dev_info)                                                  %Step through each device.
    if contains(dev_info(i).name,'(COM')                                    %If the name includes a COM port.
        j = strfind(dev_info(i).name,'(COM');                               %Find the start of the COM port number.
        dev_info(i).port = dev_info(i).name(j+1:end-1);                     %Grab the COM port number.
        dev_info(i).name(j:end) = [];                                       %Trim the port number off the name.
        dev_info(i).name = strtrim(dev_info(i).name);                       %Trim off any leading or following spaces.
        keepers(i) = 1;                                                     %Mark the device for inclusion.
    end
end
dev_info(keepers == 0) = [];                                                %Kick out all non-COM devices.


% Check the VIDs and PIDs for Vulintus devices.
usb_pid_list = Vulintus_USB_VID_PID_List;                                   %Grab the list of USB VIDs and PIDs for Vulintus devices.
for i = 1:length(dev_info)                                                  %Step through each device.    
    a = strcmpi(dev_info(i).vid,usb_pid_list(:,1));                         %Find all Vulintus devices with this VID.
    b = strcmpi(dev_info(i).pid,usb_pid_list(:,2));                         %Find all Vulintus devices with this PID.
    if any(a & b)                                                           %If there's a match for both...
        dev_info(i).name = usb_pid_list{a & b, 3};                          %Replace the device name.
    end
end

% Check the port matching file for any user-set aliases.
pairing_info = Vulintus_Serial_Port_Matching_File_Read;                     %Read in the saved pairing info.
if ~isempty(pairing_info)                                                   %If any port-pairing information was found.
    for i = 1:length(dev_info)                                              %Step through each device.    
        a = strcmpi(dev_info(i).port,{pairing_info.port});                  %Find any matches for this COM port.
        if any(a)                                                           %If there's a match...            
            dev_info(i).alias = pairing_info(a).alias;                      %Set the device alias.
            if ~any(strcmpi(dev_info(i).name,usb_pid_list(:,3)))            %If the device name wasn't set from the VID/PID...
                dev_info(i).name = pairing_info(a).name;                    %Set the device name.
            end
        end
    end
end

% Pair each active port with it's device information.
device_list = Vulintus_Load_OTSC_Device_IDs;                                %Load the OTSC device list.
device_list = values(device_list);                                          %Convert the device list to a structure.
for i = 1:length(port_list)                                                 %Step through each port.
    j = strcmpi({dev_info.port},port_list(i).com);                          %Find the port in the USB device list.    
    if any(j)                                                               %If a matching port was found...
        port_list(i).name = dev_info(j).name;                               %Grab the device name.
        port_list(i).alias = dev_info(j).alias;                             %Grab the device alias.
    elseif ~isempty(pairing_info)                                           %Otherwise...
        j = strcmpi(port_list(i).com, {pairing_info.port});                 %Check for matches in the saved pairing info.
        if any(j)                                                           %If there's pairing info for this COM port...
            port_list(i).name = pairing_info(j).name;                       %Grab the port name.
            port_list(i).alias = pairing_info(j).alias;                     %Grab the device alias.
            dev_info(end+1).port = port_list(i).com;                        %#ok<AGROW> %Add the COM port to the device list.
            dev_info(end).name = pairing_info(j).name;                      %Copy over the device name.
            dev_info(end).alias = pairing_info(j).alias;                    %Copy over the userset alias.
        end
    end
    j = strcmpi({device_list.name},port_list(i).name);                      %Match the device name to a sku.
    if any(j)                                                               %If a SKU match was found...
        port_list(i).sku = device_list(j).sku;                              %Add the SKU to the structure.
    else                                                                    %Otherwise...
        port_list(i).sku = '??-??';                                         %Set the SKU to unknown.
    end
end

% Set the output arguments.
varargout{1} = dev_info;                                                    %Return the device info (if requested).


%% ************************************************************************
function pairing_info = Vulintus_Serial_Port_Matching_File_Read

%Vulintus_Serial_Port_Matching_File_Read.m - Vulintus, Inc.
%
%   VULINTUS_SERIAL_PORT_MATCHING_FILE_READ reads in the historical COM port
%   pairing information stored in the Vulintus Common Configuration AppData
%   folder.
%
%   UPDATE LOG:
%   2024-02-27 - Drew Sloan - Function first created, branched from
%                             Vulintus_Serial_Port_List.m.
%   2025-04-29 - Drew Sloan - Switch from a TSV-formated file to a
%                             JSON-formated file.
%

config_path = Vulintus_Set_AppData_Path('Common Configuration');            %Grab the directory for common Vulintus task application data.
tsv_port_matching_file = fullfile(config_path,...
    'omnitrak_com_port_info_new.config');                                   %Set the filename for the old TSV format port matching file.
json_port_matching_file = fullfile(config_path,...
    'omnitrak_com_port_info.json');                                         %Set the filename for the new JSON format port matching file.

pairing_info = [];                                                          %Create empty brackets as the default return.

if exist(tsv_port_matching_file,'file')                                     %If the old TSV format file exists...
    if ~exist(json_port_matching_file,'file')                               %If the new JSON format file doesn't exist...
        old_data = Vulintus_TSV_File_Read(tsv_port_matching_file);          %Read in the old format data.
        for i = 1:size(old_data,1)                                          %Step through each entry in the data table.
            pairing_info(i).port = old_data{i,1};                           %Copy over the COM port.
            pairing_info(i).name = old_data{i,2};                           %Copy over the device name.
            pairing_info(i).alias = old_data{i,3};                          %Copy over the alias.
        end
        JSON_File_Write(pairing_info, json_port_matching_file);             %Create the new JSON-format file.        
    end
    delete(tsv_port_matching_file);                                         %Delete the old TSV format file.
end

if exist(json_port_matching_file,'file') && isempty(pairing_info)           %If the port matching file exists...
    pairing_info = JSON_File_Read(json_port_matching_file);                 %Read in the saved pairing info.    
end


%% ************************************************************************
function Vulintus_Serial_Port_Matching_File_Update(com_port, device_name, alias)

%Vulintus_Serial_Port_Matching_File_Update.m - Vulintus, Inc.
%
%   VULINTUS_SERIAL_PORT_MATCHING_FILE_UPDATE updates the historical COM 
%   port pairing information stored in the Vulintus Common Configuration 
%   AppData folder with the currently-connected device information.
%
%   UPDATE LOG:
%   2024-02-27 - Drew Sloan - Function first created, branched from
%                             Vulintus_Serial_Port_List.m.
%

config_path = Vulintus_Set_AppData_Path('Common Configuration');            %Grab the directory for common Vulintus task application data.
port_matching_file = fullfile(config_path,...
    'omnitrak_com_port_info_new.config');                                   %Set the filename for the port matching file.

if exist(port_matching_file,'file')                                         %If the port matching file exists...
    pairing_info = Vulintus_TSV_File_Read(port_matching_file);              %Read in the saved pairing info.
else                                                                        %Otherwise, if the port matching file doesn't exist...
    pairing_info = {};                                                      %Return an empty cell array.
end

if ~isempty(pairing_info)                                                   %If the pairing info isn't empty...
    i = ~strcmpi(pairing_info(:,1), com_port) & ...
        strcmpi(pairing_info(:,3), alias);                                  %Check to see if this alias is matched with any other COM port
    pairing_info(i,:) = [];                                                 %Kick out the outdated pairings.   
    i = strcmpi(pairing_info(:,1), com_port);                               %Check to see if this COM port is already in the port matching file.
else                                                                        %Otherwise, if the pairing info is empty...
    i = 0;                                                                  %Set the index to zero.
end

if ~any(i)                                                                  %If the port isn't in the existing list.    
    i = size(pairing_info,1) + 1;                                           %Add a new row.
end
pairing_info(i,:) = {com_port, device_name, alias};                         %Add the device information to the list.

for i = 1:size(pairing_info,1)                                              %Step through each device.
    if isempty(pairing_info{i,3})                                           %If there is no alias...
        pairing_info{i,3} = char(255);                                      %Set the alias to "ÿ".
    end
end

pairing_info = sortrows(pairing_info,[3,1,2]);                              %Sort the pairing info by alias, then COM port, then device type.

for i = 1:size(pairing_info,1)                                              %Step through each device.
    if strcmpi(pairing_info{i,3},char(255))                                 %If the alias is set to "ÿ"...
        pairing_info{i,3} = [];                                             %Set the alias to empty brackets.
    end
end

Vulintus_TSV_File_Write(pairing_info, port_matching_file);                  %Write the pairing info back to the port matching file.


%% ************************************************************************
function port = Vulintus_Serial_Select_Port(use_serialport, varargin)

%Vulintus_Serial_Select_Port.m - Vulintus, Inc., 2021
%
%   VULINTUS_SERIAL_SELECT_PORT detects available serial ports for Vulintus
%   OmniTrak devices and compares them to serial ports previously 
%   identified as being connected to OmniTrak systems.
%
%   UPDATE LOG:
%   2021-09-14 - Drew Sloan - Function first created, adapted from
%                             MotoTrak_Select_Serial_Port.m.
%   2024-02-28 - Drew Sloan - Renamed function from
%                             "OmniTrak_Select_Serial_Port" to 
%                             "Vulintus_Serial_Select_Port".
%   2024-06-06 - Drew Sloan - Added the option to use the older deprecated
%                             serial functions.
%   2025-04-22 - Drew Sloan - Added the option to specify device types.
%


port = [];                                                                  %Set the function output to empty by default.
device = {};                                                                %Assume no specified device types by default.
spec_port = [];                                                             %Seth the specified port variable to empty brackets.
if nargin > 1                                                               %If a first optional input argument was included...
    spec_port = varargin{1};                                                %The input should be a specified port number.    
end
if nargin > 1                                                               %If a second optional input argument was included...
    device = varargin{2};                                                   %The input should be a specified device type. 
end                            

dpc = get(0,'ScreenPixelsPerInch')/2.54;                                    %Grab the dots-per-centimeter of the screen.
set(0,'units','pixels');                                                    %Set the screensize units to pixels.
scrn = get(0,'ScreenSize');                                                 %Grab the screensize.
btn_w = 15*dpc;                                                             %Set the width for all buttons, in pixels.
lbl_w = 3*dpc;                                                              %Set the width for all available/busy labels.
ui_h = 1.2*dpc;                                                             %Set the height for all buttons, in pixels.
ui_sp = 0.1*dpc;                                                            %Set the spacing between UI components.
fig_w = 3*ui_sp + btn_w + lbl_w;                                            %Set the figure width.
btn_fontsize = 18;                                                          %Set the fontsize for buttons.
lbl_fontsize = 16;                                                          %Set the fontsize for labels.
ln_w = 2;                                                                   %Set the linewidth for labels.                    
    
while isempty(port)                                                         %Loop until a COM port is chosen.
    
    port_list = Vulintus_Serial_Port_List(use_serialport);                  %Find all COM ports and any associated ID information.
    
    if ~isempty(device)                                                     %If a target device was specified...
        keepers = zeros(length(port_list),1);                               %Create a matrix to mark ports for inclusion.
        for i = 1:length(port_list)                                         %Step through each entry of the port list.
            if any(strcmpi(port_list(i).sku,device))                        %If the device on the port matches a specified device...
                keepers(i) = 1;                                             %Mark the device for inclusion.
            end
        end
        if any(keepers == 1)                                                %If any matches were found...
            port_list(keepers == 0) = [];                                   %Kick out all non-matching rows.
        end
    end
    
    if isempty(port_list)                                                   %If no OmniTrak devices were found...
        errordlg(['ERROR: No Vulintus OmniTrak devices were detected '...
            'on this computer!'],'No OmniTrak Devices!');                   %Show an error in a dialog box.
        return                                                              %Skip execution of the rest of the function.
    end
    
    if ~isempty(spec_port)                                                  %If a port was specified...
        i = strcmpi({port_list.com},spec_port);                             %Find the index for the specified port.
        if any(i) && ~port_list(i).busy                                     %If the specified port is available...
            port = port_list(i).com;                                        %Return the specified port.
            return                                                          %Skip execution of the rest of the function.
        end
        spec_port = [];                                                     %Otherwise, if the specified port isn't found or is busy, ignore the input.
    end

    if isscalar(port_list) && ~port_list.busy                               %If there's only one COM port and it's available...
        port = port_list.com;                                               %Automatically select that port.
    else                                                                    %Otherwise, if no port was automatically chosen...
        fig_h = (length(port_list) + 1)*(ui_h + ui_sp) + ui_sp;             %Set the height of the port selection figure.
        fig = uifigure;                                                     %Create a UI figure.
        fig.Units = 'pixels';                                               %Set the units to pixels.
        fig.Position = [scrn(3)/2-fig_w/2, scrn(4)/2-fig_h/2,fig_w,fig_h];  %St the figure position
        fig.Resize = 'off';                                                 %Turn off figure resizing.
        fig.Name = 'Select A Serial Port';                                  %Set the figure name.
        [img, alpha_map] = Vulintus_Load_Vulintus_Logo_Circle_Social_48px;  %Use the Vulintus Social Logo for an icon.
        img = Vulintus_Behavior_Match_Icon(img, alpha_map, fig);            %Match the icon board to the figure.
        fig.Icon = img;                                                     %Set the figure icon.
        for i = 1:length(port_list)                                         %Step through each port.
            if isnt_empty_field(port_list(i),'alias')                       %If the system type is unknown...
                str = sprintf('  %s: %s (%s)', port_list(i).com,...
                    port_list(i).name, port_list(i).alias);                 %Show the port with the alias included.                      
            else                                                            %Otherwise...
                str = sprintf('  %s: %s', port_list(i).com,...
                    port_list(i).name);                                     %Show the port with just the system type included.          
            end
            x = ui_sp;                                                      %Set the x-coordinate for a button.
            y = fig_h-i*(ui_h+ui_sp);                                       %Set the y-coordinate for a button.
            temp_btn = uibutton(fig);                                       %Put a new UI button on the figure.
            temp_btn.Position = [x, y, btn_w, ui_h];                        %Set the button position.
            temp_btn.FontName = 'Arial';                                    %Set the font name.
            temp_btn.FontWeight = 'bold';                                   %Set the fontweight to bold.
            temp_btn.FontSize = btn_fontsize;                               %Set the fontsize.
            temp_btn.Text = str;                                            %Set the button text.
            temp_btn.HorizontalAlignment = 'left';                          %Align the text to the left.
            temp_btn.ButtonPushedFcn = {@OSSP_Button_press,fig,i};          %Set the button push callback.
            x = x + ui_sp + btn_w;                                          %Set the x-coordinate for a label.
            temp_ax = uiaxes(fig);                                          %Create temporary axes for making a pretty label.
            temp_ax.InnerPosition = [x, y, lbl_w, ui_h];                    %Set the axes position.
            temp_ax.XLim = [0, lbl_w];                                      %Set the x-axis limits.
            temp_ax.YLim = [0, ui_h];                                       %Set the y-axis limits.
            temp_ax.Visible = 'off';                                        %Make the axes invisible.
            temp_ax.Toolbar.Visible = 'off';                                %Make the toolbar invisible.
            temp_rect = rectangle(temp_ax);                                 %Create a rectangle in the axes.            
            temp_rect.Position = [ln_w/2, ln_w/2, lbl_w-ln_w, ui_h-ln_w];   %Set the rectangle position.
            temp_rect.Curvature = 0.5;                                      %Set the rectangle curvature.
            temp_rect.LineWidth = ln_w;                                     %Set the linewidth.
            temp_txt = text(temp_ax);                                       %Create text on the UI axes.
            if ~port_list(i).busy                                           %If the port is available...
                temp_rect.FaceColor = [0.75 1 0.75];                        %Color the label light green.
                temp_rect.EdgeColor = [0 0.5 0];                            %Color the edges dark green.
                temp_txt.String = 'AVAILABLE';                              %Set the text string to show the port availability.         
            else                                                            %Otherwise...
                temp_rect.FaceColor = [1 0.75 0.75];                        %Color the label light red.
                temp_rect.EdgeColor = [0.5 0 0];                            %Color the edges dark red.
                temp_txt.String = 'BUSY';                                   %Set the text string to show the port availability.     
            end
            temp_txt.Position = [lbl_w/2, ui_h/2];                          %Set the text position.
            temp_txt.HorizontalAlignment = 'center';                        %Align the text to the center.
            temp_txt.VerticalAlignment = 'middle';                          %Align the text to the middle.
            temp_txt.FontName = 'Arial';                                    %Set the font name.
            temp_txt.FontWeight = 'normal';                                 %Set the fontweight to bold.
            temp_txt.FontSize = lbl_fontsize;                               %Set the fontsize.
        end
        x = ui_sp;                                                          %Set the x-coordinate for a button.
        y = ui_sp;                                                          %Set the y-coordinate for a button.
        temp_btn = uibutton(fig);                                           %Put a new UI button on the figure.
        temp_btn.Position = [x, y, btn_w + lbl_w + ui_sp, ui_h];            %Set the button position.
        temp_btn.FontName = 'Arial';                                        %Set the font name.
        temp_btn.FontWeight = 'bold';                                       %Set the fontweight to bold.
        temp_btn.FontSize = btn_fontsize;                                   %Set the fontsize.
        temp_btn.Text = 'Re-Scan Ports';                                    %Set the button text.
        temp_btn.HorizontalAlignment = 'center';                            %Align the text to the center.
        temp_btn.ButtonPushedFcn = {@OSSP_Button_press,fig,0};              %Set the button push callback.
        drawnow;                                                            %Immediately update the figure.
        uiwait(fig);                                                        %Wait for the user to push a button on the pop-up figure.
        if ishandle(fig)                                                    %If the user didn't close the figure without choosing a port...
            i = fig.UserData;                                               %Grab the selected port index.
            if i ~= 0                                                       %If the user didn't press "Re-Scan"...
                port = port_list(i).com;                                    %Set the selected port.
            end
            close(fig);                                                     %Close the figure.   
        else                                                                %Otherwise, if the user closed the figure without choosing a port...
           return                                                           %Skip execution of the rest of the function.
        end
    end
end


function OSSP_Button_press(~,~,fig,i)
fig.UserData = i;                                                           %Set the figure UserData property to the specified value.
uiresume(fig);                                                              %Resume execution.


%% ************************************************************************
function Add_Msg(msgbox,new_msg)
%
%Add_Msg.m - Vulintus, Inc.
%
%   ADD_MSG displays messages in a listbox on a GUI, adding new messages to
%   the bottom of the list.
%
%   Add_Msg(listbox,new_msg) adds the string or cell array of strings
%   specified in the variable "new_msg" as the last entry or entries in the
%   ListBox or Text Area whose handle is specified by the variable 
%   "msgbox".
%
%   UPDATE LOG:
%   2016-09-09 - Drew Sloan - Fixed the bug caused by setting the
%                             ListboxTop property to an non-existent item.
%   2021-11-26 - Drew Sloan - Added the option to post status messages to a
%                             scrolling text area (uitextarea).
%   2022-02-02 - Drew Sloan - Fixed handling of the UIControl ListBox type
%                             to now use the "style" for identification.
%   2024-06-11 - Drew Sloan - Added a for loop to handle arrays of
%                             messageboxes.
%

for gui_i = 1:length(msgbox)                                                %Step through each messagebox.

    switch get(msgbox(gui_i),'type')                                        %Switch between the recognized components.
        
        case 'uicontrol'                                                    %If the messagebox is a listbox...
            switch get(msgbox(gui_i),'style')                               %Switch between the recognized uicontrol styles.
                
                case 'listbox'                                              %If the messagebox is a listbox...
                    messages = get(msgbox(gui_i),'string');                 %Grab the current string in the messagebox.
                    if isempty(messages)                                    %If there's no messages yet in the messagebox...
                        messages = {};                                      %Create an empty cell array to hold messages.
                    elseif ~iscell(messages)                                %If the string property isn't yet a cell array...
                        messages = {messages};                              %Convert the messages to a cell array.
                    end
                    messages{end+1} = new_msg;                              %Add the new message to the listbox.
                    set(msgbox(gui_i),'string',messages);                   %Update the strings in the listbox.
                    set(msgbox(gui_i),'value',length(messages),...
                        'ListboxTop',length(messages));                     %Set the value of the listbox to the newest messages.
                    set(msgbox(gui_i),'min',0,...
                        'max',2',...
                        'selectionhighlight','off',...
                        'value',[]);                                        %Set the properties on the listbox to make it look like a simple messagebox.
                    drawnow;                                                %Update the GUI.
                    
            end
            
        case 'uitextarea'                                                   %If the messagebox is a uitextarea...
            messages = msgbox(gui_i).Value;                                 %Grab the current strings in the messagebox.
            if ~iscell(messages)                                            %If the string property isn't yet a cell array...
                messages = {messages};                                      %Convert the messages to a cell array.
            end
            checker = 1;                                                    %Create a matrix to check for non-empty cells.
            for i = 1:numel(messages)                                       %Step through each message.
                if ~isempty(messages{i})                                    %If there any non-empty messages...
                    checker = 0;                                            %Set checker equal to zero.
                end
            end
            if checker == 1                                                 %If all messages were empty.
                messages = {};                                              %Set the messages to an empty cell array.
            end
            messages{end+1} = new_msg;                                      %Add the new message to the listbox.
            msgbox(gui_i).Value = messages;                                 %Update the strings in the Text Area.        
            drawnow;                                                        %Update the GUI.
            scroll(msgbox(gui_i),'bottom');                                 %Scroll to the bottom of the Text Area.
    end

end
        


%% ************************************************************************
function Append_Msg(msgbox,new_txt)

%
%APPEND_MSG.m - Vulintus, Inc., 2023
%
%   APPEND_MSG displays messages in a listbox on a GUI, adding the 
%   specified text to the message at the bottom of the list.
%
%   Append_Msg(msgbox,new_txt) adds the text passed in the variable
%   "new_txt" to the last entry in the listbox or text area whose handle is
%   specified by the variable "msgbox".
%
%   UPDATE LOG:
%   2023-09-27 - Drew Sloan - Function first created, adapted from
%                             "Replace_Msg.m".
%

switch get(msgbox,'type')                                                   %Switch between the recognized components.
    
    case 'uicontrol'                                                        %If the messagebox is a listbox...
        switch get(msgbox,'style')                                          %Switch between the recognized uicontrol styles.
            
            case 'listbox'                                                  %If the messagebox is a listbox...
                messages = get(msgbox,'string');                            %Grab the current string in the messagebox.
                if isempty(messages)                                        %If there's no messages yet in the messagebox...
                    messages = {};                                          %Create an empty cell array to hold messages.
                elseif ~iscell(messages)                                    %If the string property isn't yet a cell array...
                    messages = {messages};                                  %Convert the messages to a cell array.
                end
                if iscell(new_txt)                                          %If the new message is a cell array...
                    new_txt = new_txt{1};                                   %Convert the first cell of the new message to characters.
                end
                messages{end} = horzcat(messages{end},new_txt);             %Add the new text to the end of the last message.
                set(msgbox,'string',messages);                              %Updat the list items.
                set(msgbox,'value',length(messages));                       %Set the value of the listbox to the newest messages.
                drawnow;                                                    %Update the GUI.
                a = get(msgbox,'listboxtop');                               %Grab the top-most value of the listbox.
                set(msgbox,'min',0,...
                    'max',2',...
                    'selectionhighlight','off',...
                    'value',[],...
                    'listboxtop',a);                                        %Set the properties on the listbox to make it look like a simple messagebox.
                drawnow;                                                    %Update the GUI.
                
        end
        
    case 'uitextarea'                                                       %If the messagebox is a uitextarea...
        messages = msgbox.Value;                                            %Grab the current strings in the messagebox.
        if ~iscell(messages)                                                %If the string property isn't yet a cell array...
            messages = {messages};                                          %Convert the messages to a cell array.
        end
        checker = 1;                                                        %Create a matrix to check for non-empty cells.
        for i = 1:numel(messages)                                           %Step through each message.
            if ~isempty(messages{i})                                        %If there any non-empty messages...
                checker = 0;                                                %Set checker equal to zero.
            end
        end
        if checker == 1                                                     %If all messages were empty.
            messages = {};                                                  %Set the messages to an empty cell array.
        end
        if iscell(new_txt)                                                  %If the new message is a cell array...
            new_txt = new_txt{1};                                           %Convert the first cell of the new message to characters.
        end
        messages{end} = horzcat(messages{end},new_txt);                     %Add the new text to the end of the last message.
        msgbox.Value = messages';                                           %Update the strings in the Text Area.
        scroll(msgbox,'bottom');                                            %Scroll to the bottom of the Text Area.
        drawnow;                                                            %Update the GUI.
        
end


%% ************************************************************************
function data = JSON_File_Read(file)

%
% JSON_File_Read.m
% 
%   copyright 2023, Vulintus, Inc.
%
%   JSON_FILE_READ reads in data from a JSON-formatted text file.
%   
%   UPDATE LOG:
%   2023-06-08 - Drew Sloan - Function first created, adapted from
%                             "Vulintus_Read_TSV_File.m".
%   2024-03-08 - Drew Sloan - Renamed file from "Vulintus_Read_JSON_File"
%                             to "Vulintus_JSON_File_Read".
%   2025-01-21 - Drew Sloan - Commented out the double-forward-slash
%                             handling. Fully delete later if no problems 
%                             arise.
%   2025-02-03 - Drew Sloan - Renamed "Vulintus_JSON_File_Read" to simply
%                             "JSON_File_Read" for more general use.
%                           - Uncommented double-forward-slash handling.
%   2025-02-24 - Drew Sloan - Fixed handling of escaped double quotes.
%


[fid, errmsg] = fopen(file,'rt');                                           %Open the stage configuration file saved previously for reading as text.
if fid == -1                                                                %If the file could not be opened...
    str = sprintf(['Could not read the specified JSON file:\n\n%s\n\n'...
        'Error:\n\n%s'],file,errmsg);                                       %Create a warning string.
    warndlg(str,'JSON_File_Read Error');                                    %Show a warning.
    close(fid);                                                             %Close the file.
    data = [];                                                              %Set the output data variable to empty brackets.
    return                                                                  %Skip execution of the rest of the function.
end
txt = fread(fid,'*char')';                                                  %Read in the file data as text.
fclose(fid);                                                                %Close the configuration file.
txt = strrep(txt,'\','\\');                                                 %Replace all single forward slashes with two slashes.
txt = strrep(txt,'\\\','\\');                                               %Replace all triple forward slashes with two slashes.
txt = strrep(txt,'\\"','\"');                                               %Replace all double forward slashes preceding double quotes with one slash.
data = jsondecode(txt);                                                     %Convert the text to data.


%% ************************************************************************
function JSON_File_Write(data,filename)

%
% JSON_File_Write.m
% 
%   copyright 2023, Vulintus, Inc.
%
%   JSON_FILE_WRITE saves the elements of the variable "data" to a JSON-
%   formatted text file specified by "filename", with "data" being any 
%   supported MATLAB data type.
%   
%   UPDATE LOG:
%   2023-06-08 - Drew Sloan - Function first created, adapted from
%                             "Vulintus_Write_TSV_File.m".
%   2024-03-08 - Drew Sloan - Added the "PrettyPrint" option to the
%                             "jsonencode" function.
%                             Renamed file from "Vulintus_Write_JSON_File"
%                             to "Vulintus_JSON_File_Write".
%   2025-02-03 - Drew Sloan - Renamed "Vulintus_JSON_File_Write" to simply
%                             "JSON_File_Write" for more general use.
%


[fid, errmsg] = fopen(filename,'wt');                                       %Open a text-formatted configuration file to save the stage information.
if fid == -1                                                                %If a file could not be created...
    str = sprintf(['Could not create the specified JSON file:\n\n%s\n\n'...
        'Error:\n\n%s'],filename,errmsg);                                   %Create a warning string.
    warndlg(str,'Write_JSON_File Error');                                   %Show a warning.
    return                                                                  %Skip execution of the rest of the function.
end
txt = jsonencode(data,PrettyPrint=true);                                    %Convert the data to JSON-formatted text.
if any(txt == '\')                                                          %If there's any forward slashes...    
    txt = strrep(txt,'\','\\');                                             %Replace all single forward slashes with two slashes.
    k = strfind(txt,'\\\');                                                 %Look for any triple forward slashes...
    txt(k) = [];                                                            %Kick out the extra forward slashes.
end
fprintf(fid,txt);                                                           %Write the text to the file.
fclose(fid);                                                                %Close the JSON file.    


%% ************************************************************************
function appdata_path = Set_AppData_Local_Path(varargin)

%
% Set_AppData_Local_Path.m
% 
%   copyright 2025, Vulintus, Inc.
%
%   SET_APPDATA_LOCAL_PATH finds and/or creates the the local application 
%   data folder and any subfolders specified in the variable input
%   arguments.
%   
%   UPDATE LOG:
%   2025-02-03 - Drew Sloan - Function first created, adapted from 
%                             "Vulintus_Set_AppData_Path.m".
%


appdata_path = winqueryreg('HKEY_CURRENT_USER',...
        ['Software\Microsoft\Windows\CurrentVersion\' ...
        'Explorer\Shell Folders'],'Local AppData');                         %Grab the local application data directory.    

if nargin == 0                                                              %If there were no input arguments...
    return                                                                  %Skip the rest of the function and return just the basic appdata path.
end

for i = 1:length(varargin)                                                  %Step through each variable input argument.
    if ~ischar(varargin{i})                                                 %If the input argument isn't a character array.
        error('ERROR IN %s: Inputs must be character arrays!',...
            upper(mfilename));                                              %Show an error.
    end
    appdata_path = fullfile(appdata_path,varargin{i});                      %Append each new subfolder to the directory name.
    if ~exist(appdata_path,'dir')                                           %If the directory doesn't already exist...
        [status, msg, ~] = mkdir(appdata_path);                             %Create the directory.
        if status ~= 1                                                      %If the directory couldn't be created...
            error(['ERROR IN %s: Unable to create application data'...
                ' directory:\n\t%s\n\t%s'], upper(mfilename),...
                appdata_path,msg);                                          %Show an error.
        end
    end
end
appdata_path = fullfile(appdata_path,'\');                                  %Add a forward slash to the path.


%% ************************************************************************
function data = Vulintus_TSV_File_Read(file)

%
%Vulintus_TSV_File_Read.m - Vulintus, Inc.
%
%   VULINTUS_TSV_FILE_READ reads in data from a spreadsheet-formated TSV
%   file.
%   
%   UPDATE LOG:
%   2016-09-12 - Drew Sloan - Moved the TSV-reading code from
%                             Vulintus_Read_Stages.m to this function.
%   2016-09-13 - Drew Sloan - Generalized the MotoTrak TSV-reading program
%                             to also work with OmniTrak and future
%                             behavior programs.
%   2022-04-26 - Drew sloan - Replaced "sprintf('\n')" with MATLAB's
%                             built-in "newline" function.
%   2024-05-06 - Drew Sloan - Renamed from "Vulintus_Read_TSV_File" to 
%                             "Vulintus_TSV_File_Read".
%


[fid, errmsg] = fopen(file,'rt');                                           %Open the stage configuration file saved previously for reading as text.
if fid == -1                                                                %If the file could not be opened...
    warndlg(sprintf(['Could not open the stage file '...
        'in:\n\n%s\n\nError:\n\n%s'],file,...
        errmsg),'Vulintus File Read Error');                                %Show a warning.
    data = [];                                                              %Set the output data variable to empty brackets.
    return                                                                  %Return to the calling function.
end
txt = fread(fid,'*char')';                                                  %Read in the file data as text.
fclose(fid);                                                                %Close the configuration file.
tab = sprintf('\t');                                                        %Make a tab string for finding delimiters.
a = find(txt == tab | txt == newline);                                      %Find all delimiters in the string.
a = [0, a, length(txt)+1];                                                  %Add indices for the first and last elements of the string.
txt = [txt, newline];                                                       %Add a new line to the end of the string to avoid confusing the spreadsheet-reading loop.
column = 1;                                                                 %Count across columns.
row = 1;                                                                    %Count down rows.
data = {};                                                                  %Make a cell array to hold the spreadsheet-formated data.
for i = 2:length(a)                                                         %Step through each entry in the string.
    if a(i) == a(i-1)+1                                                     %If there is no entry for this cell...
        data{row,column} = [];                                              %...assign an empty matrix.
    else                                                                    %Otherwise...
        data{row,column} = txt((a(i-1)+1):(a(i)-1));                        %...read one entry from the string.
    end
    if txt(a(i)) == tab                                                     %If the delimiter was a tab or a comma...
        column = column + 1;                                                %...advance the column count.
    else                                                                    %Otherwise, if the delimiter was a new-line...
        column = 1;                                                         %...reset the column count to 1...
        row = row + 1;                                                      %...and add one to the row count.
    end
end


%% ************************************************************************
function Vulintus_TSV_File_Write(data,filename)

%
%Vulintus_TSV_File_Write.m - Vulintus, Inc.
%
%   VULINTUS_TSV_FILE_WRITE saves the elements of the cell array "data" in
%   a TSV-formatted spreadsheet specified by "filename".
%   
%   UPDATE LOG:
%   2016-09-13 - Drew Sloan - Generalized the MotoTrak TSV-writing program
%                             to also work with OmniTrak and future 
%                             behavior programs.
%   2024-05-06 - Drew Sloan - Renamed from "Vulintus_Write_TSV_File" to 
%                             "Vulintus_TSV_File_Write".
%


[fid, errmsg] = fopen(filename,'wt');                                       %Open a text-formatted configuration file to save the stage information.
if fid == -1                                                                %If a file could not be created...
    warndlg(sprintf(['Could not create stage file backup '...
        'in:\n\n%s\n\nError:\n\n%s'],filename,...
        errmsg),'OmniTrak File Write Error');                               %Show a warning.
end
for i = 1:size(data,1)                                                      %Step through the rows of the stage data.
    for j = 1:size(data,2)                                                  %Step through the columns of the stage data.
        data{i,j}(data{i,j} < 32) = [];                                     %Kick out all special characters.
        fprintf(fid,'%s',data{i,j});                                        %Write each element of the stage data as tab-separated values.
        if j < size(data,2)                                                 %If this isn't the end of a row...
            fprintf(fid,'\t');                                              %Write a tab to the file.
        elseif i < size(data,1)                                             %Otherwise, if this isn't the last row...
            fprintf(fid,'\n');                                              %Write a carriage return to the file.
        end
    end
end
fclose(fid);                                                                %Close the stages TSV file.    


%% ************************************************************************
function waitbar = big_waitbar(varargin)

figsize = [2,16];                                                           %Set the default figure size, in centimeters.
barcolor = 'b';                                                             %Set the default waitbar color.
titlestr = 'Waiting...';                                                    %Set the default waitbar title.
txtstr = 'Waiting...';                                                      %Set the default waitbar string.
val = 0;                                                                    %Set the default value of the waitbar to zero.

str = {'FigureSize','Color','Title','String','Value'};                      %List the allowable parameter names.
for i = 1:2:length(varargin)                                                %Step through any optional input arguments.
    if ~ischar(varargin{i}) || ~any(strcmpi(varargin{i},str))               %If the first optional input argument isn't one of the expected property names...
        beep;                                                               %Play the Matlab warning noise.
        cprintf('red','%s\n',['ERROR IN BIG_WAITBAR: Property '...
            'name not recognized! Optional input properties are:']);        %Show an error.
        for j = 1:length(str)                                               %Step through each allowable parameter name.
            cprintf('red','\t%s\n',str{j});                                 %List each parameter name in the command window, in red.
        end
        return                                                              %Skip execution of the rest of the function.
    else                                                                    %Otherwise...
        if strcmpi(varargin{i},'FigureSize')                                %If the optional input property is "FigureSize"...
            figsize = varargin{i+1};                                        %Set the figure size to that specified, in centimeters.            
        elseif strcmpi(varargin{i},'Color')                                 %If the optional input property is "Color"...
            barcolor = varargin{i+1};                                       %Set the waitbar color the specified color.
        elseif strcmpi(varargin{i},'Title')                                 %If the optional input property is "Title"...
            titlestr = varargin{i+1};                                       %Set the waitbar figure title to the specified string.
        elseif strcmpi(varargin{i},'String')                                %If the optional input property is "String"...
            txtstr = varargin{i+1};                                         %Set the waitbar text to the specified string.
        elseif strcmpi(varargin{i},'Value')                                 %If the optional input property is "Value"...
            val = varargin{i+1};                                            %Set the waitbar value to the specified value.
        end
    end    
end

orig_units = get(0,'units');                                                %Grab the current system units.
set(0,'units','centimeters');                                               %Set the system units to centimeters.
pos = get(0,'Screensize');                                                  %Grab the screensize.
h = figsize(1);                                                             %Set the height of the figure.
w = figsize(2);                                                             %Set the width of the figure.
fig = figure('numbertitle','off',...
    'name',titlestr,...
    'units','centimeters',...
    'Position',[pos(3)/2-w/2, pos(4)/2-h/2, w, h],...
    'menubar','none',...
    'resize','off');                                                        %Create a figure centered in the screen.
ax = axes('units','centimeters',...
    'position',[0.25,0.25,w-0.5,h/2-0.3],...
    'parent',fig);                                                          %Create axes for showing loading progress.
if val > 1                                                                  %If the specified value is greater than 1...
    val = 1;                                                                %Set the value to 1.
elseif val < 0                                                              %If the specified value is less than 0...
    val = 0;                                                                %Set the value to 0.
end    
obj = fill(val*[0 1 1 0 0],[0 0 1 1 0],barcolor,'edgecolor','k');           %Create a fill object to show loading progress.
set(ax,'xtick',[],'ytick',[],'box','on','xlim',[0,1],'ylim',[0,1]);         %Set the axis limits and ticks.
txt = uicontrol(fig,'style','text','units','centimeters',...
    'position',[0.25,h/2+0.05,w-0.5,h/2-0.3],'fontsize',10,...
    'horizontalalignment','left','backgroundcolor',get(fig,'color'),...
    'string',txtstr);                                                       %Create a text object to show the current point in the wait process.  
set(0,'units',orig_units);                                                  %Set the system units back to the original units.

waitbar.type = 'big_waitbar';                                               %Set the structure type.
waitbar.title = @(str)SetTitle(fig,str);                                    %Set the function for changing the waitbar title.
waitbar.string = @(str)SetString(fig,txt,str);                              %Set the function for changing the waitbar string.
% waitbar.value = @(val)SetVal(fig,obj,val);                                  %Set the function for changing waitbar value.
waitbar.value = @(varargin)GetSetVal(fig,obj,varargin{:});                  %Set the function for reading/setting the waitbar value.
waitbar.color = @(val)SetColor(fig,obj,val);                                %Set the function for changing waitbar color.
waitbar.close = @()CloseWaitbar(fig);                                       %Set the function for closing the waitbar.
waitbar.isclosed = @()WaitbarIsClosed(fig);                                 %Set the function for checking whether the waitbar figure is closed.

drawnow;                                                                    %Immediately show the waitbar.


%% This function sets the name/title of the waitbar figure.
function SetTitle(fig,str)
if ishandle(fig)                                                            %If the waitbar figure is still open...
    set(fig,'name',str);                                                    %Set the figure name to the specified string.
    drawnow;                                                                %Immediately update the figure.
else                                                                        %Otherwise...
    warning('Cannot update the waitbar figure. It has been closed.');       %Show a warning.
end


%% This function sets the string on the waitbar figure.
function SetString(fig,txt,str)
if ishandle(fig)                                                            %If the waitbar figure is still open...
    set(txt,'string',str);                                                  %Set the string in the text object to the specified string.
    drawnow;                                                                %Immediately update the figure.
else                                                                        %Otherwise...
    warning('Cannot update the waitbar figure. It has been closed.');       %Show a warning.
end


% %% This function sets the current value of the waitbar.
% function SetVal(fig,obj,val)
% if ishandle(fig)                                                            %If the waitbar figure is still open...
%     if val > 1                                                              %If the specified value is greater than 1...
%         val = 1;                                                            %Set the value to 1.
%     elseif val < 0                                                          %If the specified value is less than 0...
%         val = 0;                                                            %Set the value to 0.
%     end
%     set(obj,'xdata',val*[0 1 1 0 0]);                                       %Set the patch object to extend to the specified value.
%     drawnow;                                                                %Immediately update the figure.
% else                                                                        %Otherwise...
%     warning('Cannot update the waitbar figure. It has been closed.');       %Show a warning.
% end


%% This function reads/sets the waitbar value.
function val = GetSetVal(fig,obj,varargin)
if ishandle(fig)                                                            %If the waitbar figure is still open...
    if nargin > 2                                                           %If a value was passed.
        val = varargin{1};                                                  %Grab the specified value.
        if val > 1                                                          %If the specified value is greater than 1...
            val = 1;                                                        %Set the value to 1.
        elseif val < 0                                                      %If the specified value is less than 0...
            val = 0;                                                        %Set the value to 0.
        end
        set(obj,'xdata',val*[0 1 1 0 0]);                                   %Set the patch object to extend to the specified value.
        drawnow;                                                            %Immediately update the figure.
    else                                                                    %Otherwise...
        val = get(obj,'xdata');                                             %Grab the x-coordinates from the patch object.
        val = val(2);                                                       %Return the right-hand x-coordinate.
    end
else                                                                        %Otherwise...
    warning('Cannot access the waitbar figure. It has been closed.');       %Show a warning.
end
    


%% This function sets the color of the waitbar.
function SetColor(fig,obj,val)
if ishandle(fig)                                                            %If the waitbar figure is still open...
    set(obj,'facecolor',val);                                               %Set the patch object to have the specified facecolor.
    drawnow;                                                                %Immediately update the figure.
else                                                                        %Otherwise...
    warning('Cannot update the waitbar figure. It has been closed.');       %Show a warning.
end


%% This function closes the waitbar figure.
function CloseWaitbar(fig)
if ishandle(fig)                                                            %If the waitbar figure is still open...
    close(fig);                                                             %Close the waitbar figure.
    drawnow;                                                                %Immediately update the figure to allow it to close.
end


%% This function returns a logical value indicate whether the waitbar figure has been closed.
function isclosed = WaitbarIsClosed(fig)
isclosed = ~ishandle(fig);                                                  %Check to see if the figure handle is still a valid handle.


%% ************************************************************************
function not_empty = isnt_empty_field(obj, fieldname, varargin)

%
% isnt_empty_field.m
%   
%   copyright 2024, Vulintus, Inc.
%
%   ISNT_EMPTY_FIELD is a recursive function that checks if the all of 
%   specified fields/subfields exist in the in the specified structure 
%   ("structure"), and then checks if the last subfield is empty.
%
%   UPDATE LOG:
%   2024-08-27 - Drew Sloan - Function first created.
%   2024-11-11 - Drew Sloan - Created complementary function
%                             "is_empty_field" to check for the reverse
%                             case.
%   2025-02-17 - Drew Sloan - Added an "isprop" check to be able to check
%                             class properties like structure fields.
%


switch class(obj)                                                           %Switch between the different recognized classes.
    case 'struct'                                                           %Structure.
        not_empty = isfield(obj, fieldname);                                %Check to see if the fieldname exists.
    case {'Vulintus_Behavior_Class','Vulintus_OTSC_Handler','datetime'}     %Vulintus classes.
        not_empty = isprop(obj, fieldname);                                 %Check to see if the property exists.     
    otherwise                                                               %For all other cases...
        not_empty = ~isempty(obj);                                          %Check to see if the object is empty.                   
end
if ~not_empty                                                               %If the field doesn't exist...
    return                                                                  %Skip the rest of the function.
end

if nargin == 2 || isempty(varargin)                                         %If only one field name was passed...    
    if (not_empty)                                                          %If the field exists...
        not_empty = ~isempty(obj.(fieldname));                              %Check to see if the field isn't empty.
    end
elseif nargin == 3                                                          %If a field name and one subfield name was passed...
    not_empty = isnt_empty_field(obj.(fieldname),varargin{1});              %Recursively call this function to check the subfield.
else                                                                        %Otherwise...
    not_empty = isnt_empty_field(obj.(fieldname),varargin{1},...
        varargin{2:end});                                                   %Recursively call this function to handle all subfields.
end


%% ************************************************************************
function [im, varargout] = Vulintus_Load_Vulintus_Logo_Circle_Social_48px

%VULINTUS_LOAD_VULINTUS_LOGO_CIRCLE_SOCIAL_48PX
%
%	Vulintus, Inc.
%
%	Software icon defined in script.
%
%	This function was programmatically generated: 28-Feb-2024 12:39:59
%

im = uint8(zeros(48,48,3));
im(:,:,1) = [	 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   0,   9,  18,  14,   7,   3,   3,   7,  14,  18,   9,   0,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   2,  15,   7,  63, 133, 173, 212, 228, 239, 239, 228, 211, 172, 132,  61,   7,  15,   2,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  10,   8,  77, 178, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 249, 177,  76,   7,  10,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   6,   8, 105, 225, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224, 102,   8,   6,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  13,  60, 217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  57,  13,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255,   3,   9, 143, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 142,   9,   3, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255,   5,  15, 199, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 198,  15,   5, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255,   5,  21, 216, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  21,   5, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255,   3,  15, 216, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  15,   3, 255, 255, 255, 255, 255;
				 255, 255, 255, 255,   0,   9, 200, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 198,   9,   0, 255, 255, 255, 255;
				 255, 255, 255,   0,  13, 144, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 142,  13,   0, 255, 255, 255;
				 255, 255, 255,   6,  60, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,  58,   8, 255, 255, 255;
				 255, 255,   0,   9, 217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,   8,   0, 255, 255;
				 255, 255,  10, 105, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 102,  12, 255, 255;
				 255,   0,   8, 225, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224,   7,   0, 255;
				 255,   2,  77, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  76,   2, 255;
				 255,  15, 178, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 176,  16, 255;
				   0,   7, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248,   7,   0;
				   0,  63, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 243, 255,  59,   0;
				   9, 132, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 190, 110, 132, 255, 131,   9;
				  18, 174, 255, 176,  34,  34,  92, 119, 119, 119, 240,  97,  54,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  75,  77, 246, 150, 255, 171,  18;
				  13, 211, 255, 249,  30,   0,  91, 255, 255, 255, 210,   1, 173, 255, 255, 255, 255, 255,  94, 107, 255, 158, 162, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213, 120, 133, 255, 209,  13;
				   7, 229, 255, 255, 148,   0,   3, 218, 255, 255,  87,  44, 253, 255, 255, 255, 255, 255,  35,  54, 255,  64,  81, 255, 255, 255, 255, 255, 255, 255, 231, 122, 193, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 255, 227,   8;
				   3, 241, 255, 255, 247,  25,   0,  97, 255, 215,   2, 148, 170, 219, 255, 184, 186, 255,  35,  54, 255, 181, 188, 255, 177, 212, 194, 158, 235, 255, 125,   0, 110, 209, 211, 170, 244, 244, 170, 211, 255, 226, 158, 166, 240, 255, 240,   3;
				   3, 241, 255, 255, 255, 141,   0,   5, 222,  92,  40, 195,   0, 146, 255,  40,  48, 255,  35,  54, 255,  34,  53, 255,  25,  26,   2,   0,  45, 255,  22,   0,  11, 127, 122,   0, 221, 221,   0, 122, 226,  13,  40,  41, 212, 255, 240,   3;
				   7, 229, 255, 255, 255, 244,  21,   0,  72,   3, 162, 198,   0, 145, 255,  39,  47, 255,  35,  54, 255,  34,  53, 255,  27,  32, 247,  98,   0, 227, 186,   0, 165, 255, 124,   0, 221, 220,   0, 122, 185,   0,  90, 229, 255, 255, 227,   8;
				  13, 211, 255, 255, 255, 255, 135,   0,   0,  35, 251, 201,   0, 142, 255,  37,  46, 255,  35,  54, 255,  34,  53, 255,  28,  58, 255, 128,   0, 214, 188,   0, 164, 255, 130,   0, 218, 219,   0, 121, 252, 116,  10,  11, 197, 255, 209,  13;
				  18, 173, 255, 255, 255, 255, 242,  18,   0, 156, 255, 217,   0,  68, 172,   8,  44, 255,  35,  54, 255,  34,  53, 255,  29,  58, 255, 130,   0, 212, 198,   0,  98, 221, 146,   0, 125, 124,   0, 119, 233, 206, 184,   0, 125, 255, 171,  18;
				   9, 132, 255, 255, 255, 255, 255, 129,  30, 250, 255, 255,  83,   0,  30,  59,  41, 255,  35,  54, 255,  34,  53, 255,  30,  59, 255, 131,   0, 212, 249,  50,   0, 127, 230,  34,   0,  71,  16, 116, 173,   3,   0,  36, 216, 255, 131,   9;
				   0,  61, 255, 255, 255, 255, 255, 245, 224, 255, 255, 255, 255, 235, 251, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 235, 254, 255, 253, 234, 255, 255, 255, 255, 246, 227, 255, 255, 255,  58,   0;
				   0,   7, 249, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248,   6,   0;
				 255,  15, 177, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 175,  16, 255;
				 255,   2,  76, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  75,   2, 255;
				 255,   0,   7, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223,   8,   0, 255;
				 255, 255,  10, 102, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 100,  11, 255, 255;
				 255, 255,   0,   8, 214, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,   8,   0, 255, 255;
				 255, 255, 255,   6,  57, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,  56,   6, 255, 255, 255;
				 255, 255, 255,   0,  13, 141, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 140,  13,   0, 255, 255, 255;
				 255, 255, 255, 255,   0,   9, 198, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 196,   8,   0, 255, 255, 255, 255;
				 255, 255, 255, 255, 255,   3,  13, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 214,  13,   0, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255,   5,  21, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 214,  20,   5, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255,   5,  13, 197, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 196,  14,   5, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255,   3,   9, 142, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 140,   8,   0, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  13,  57, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,  56,  13,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   6,   8, 102, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223, 100,   8,   6,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  10,   7,  75, 176, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 175,  74,   8,  11,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   2,  16,   7,  60, 132, 172, 210, 227, 239, 239, 227, 209, 171, 131,  59,   6,  16,   2,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   0,   9,  18,  14,   7,   3,   3,   8,  14,  18,   9,   0,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255];
im(:,:,2) = [	 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   0,   9,  18,  14,   7,   3,   3,   7,  14,  18,   9,   0,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   2,  15,   7,  63, 133, 173, 212, 228, 239, 239, 228, 211, 172, 132,  61,   7,  15,   2,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  10,   8,  77, 178, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 249, 177,  76,   7,  10,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   6,   8, 105, 225, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224, 102,   8,   6,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  13,  60, 217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  57,  13,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255,   3,   9, 143, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 142,   9,   3, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255,   5,  15, 199, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 198,  15,   5, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255,   5,  21, 216, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  21,   5, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255,   3,  15, 216, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  15,   3, 255, 255, 255, 255, 255;
				 255, 255, 255, 255,   0,   9, 200, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 198,   9,   0, 255, 255, 255, 255;
				 255, 255, 255,   0,  13, 144, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 142,  13,   0, 255, 255, 255;
				 255, 255, 255,   6,  60, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,  58,   8, 255, 255, 255;
				 255, 255,   0,   9, 217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,   8,   0, 255, 255;
				 255, 255,  10, 105, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 102,  12, 255, 255;
				 255,   0,   8, 225, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224,   7,   0, 255;
				 255,   2,  77, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  76,   2, 255;
				 255,  15, 178, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 176,  16, 255;
				   0,   7, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248,   7,   0;
				   0,  63, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 243, 255,  59,   0;
				   9, 132, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 190, 110, 132, 255, 131,   9;
				  18, 174, 255, 176,  34,  34,  92, 119, 119, 119, 240,  97,  54,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  75,  77, 246, 150, 255, 171,  18;
				  13, 211, 255, 249,  30,   0,  91, 255, 255, 255, 210,   1, 173, 255, 255, 255, 255, 255,  94, 107, 255, 158, 162, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213, 120, 133, 255, 209,  13;
				   7, 229, 255, 255, 148,   0,   3, 218, 255, 255,  87,  44, 253, 255, 255, 255, 255, 255,  35,  54, 255,  64,  81, 255, 255, 255, 255, 255, 255, 255, 231, 122, 193, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 255, 227,   8;
				   3, 241, 255, 255, 247,  25,   0,  97, 255, 215,   2, 148, 170, 219, 255, 184, 186, 255,  35,  54, 255, 181, 188, 255, 177, 212, 194, 158, 235, 255, 125,   0, 110, 209, 211, 170, 244, 244, 170, 211, 255, 226, 158, 166, 240, 255, 240,   3;
				   3, 241, 255, 255, 255, 141,   0,   5, 222,  92,  40, 195,   0, 146, 255,  40,  48, 255,  35,  54, 255,  34,  53, 255,  25,  26,   2,   0,  45, 255,  22,   0,  11, 127, 122,   0, 221, 221,   0, 122, 226,  13,  40,  41, 212, 255, 240,   3;
				   7, 229, 255, 255, 255, 244,  21,   0,  72,   3, 162, 198,   0, 145, 255,  39,  47, 255,  35,  54, 255,  34,  53, 255,  27,  32, 247,  98,   0, 227, 186,   0, 165, 255, 124,   0, 221, 220,   0, 122, 185,   0,  90, 229, 255, 255, 227,   8;
				  13, 211, 255, 255, 255, 255, 135,   0,   0,  35, 251, 201,   0, 142, 255,  37,  46, 255,  35,  54, 255,  34,  53, 255,  28,  58, 255, 128,   0, 214, 188,   0, 164, 255, 130,   0, 218, 219,   0, 121, 252, 116,  10,  11, 197, 255, 209,  13;
				  18, 173, 255, 255, 255, 255, 242,  18,   0, 156, 255, 217,   0,  68, 172,   8,  44, 255,  35,  54, 255,  34,  53, 255,  29,  58, 255, 130,   0, 212, 198,   0,  98, 221, 146,   0, 125, 124,   0, 119, 233, 206, 184,   0, 125, 255, 171,  18;
				   9, 132, 255, 255, 255, 255, 255, 129,  30, 250, 255, 255,  83,   0,  30,  59,  41, 255,  35,  54, 255,  34,  53, 255,  30,  59, 255, 131,   0, 212, 249,  50,   0, 127, 230,  34,   0,  71,  16, 116, 173,   3,   0,  36, 216, 255, 131,   9;
				   0,  61, 255, 255, 255, 255, 255, 245, 224, 255, 255, 255, 255, 235, 251, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 235, 254, 255, 253, 234, 255, 255, 255, 255, 246, 227, 255, 255, 255,  58,   0;
				   0,   7, 249, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248,   6,   0;
				 255,  15, 177, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 175,  16, 255;
				 255,   2,  76, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  75,   2, 255;
				 255,   0,   7, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223,   8,   0, 255;
				 255, 255,  10, 102, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 100,  11, 255, 255;
				 255, 255,   0,   8, 214, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,   8,   0, 255, 255;
				 255, 255, 255,   6,  57, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,  56,   6, 255, 255, 255;
				 255, 255, 255,   0,  13, 141, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 140,  13,   0, 255, 255, 255;
				 255, 255, 255, 255,   0,   9, 198, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 196,   8,   0, 255, 255, 255, 255;
				 255, 255, 255, 255, 255,   3,  13, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 214,  13,   0, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255,   5,  21, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 214,  20,   5, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255,   5,  13, 197, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 196,  14,   5, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255,   3,   9, 142, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 140,   8,   0, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  13,  57, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,  56,  13,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   6,   8, 102, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223, 100,   8,   6,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  10,   7,  75, 176, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 175,  74,   8,  11,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   2,  16,   7,  60, 132, 172, 210, 227, 239, 239, 227, 209, 171, 131,  59,   6,  16,   2,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   0,   9,  18,  14,   7,   3,   3,   8,  14,  18,   9,   0,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255];
im(:,:,3) = [	 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   0,  10,  19,  16,   8,   4,   4,   8,  16,  19,  10,   0,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   2,  17,   8,  64, 133, 173, 212, 228, 239, 239, 228, 211, 172, 132,  62,   8,  17,   2,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  12,   9,  78, 178, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 249, 177,  77,   8,  12,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   6,   9, 106, 225, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224, 103,   9,   6,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  14,  61, 217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  59,  14,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255,   3,  10, 143, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 142,  10,   3, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255,   5,  16, 199, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 198,  17,   5, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255,   5,  22, 216, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  22,   5, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255,   3,  16, 216, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,  17,   3, 255, 255, 255, 255, 255;
				 255, 255, 255, 255,   0,  10, 200, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 198,  10,   0, 255, 255, 255, 255;
				 255, 255, 255,   0,  14, 144, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 142,  14,   0, 255, 255, 255;
				 255, 255, 255,   6,  61, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,  59,   8, 255, 255, 255;
				 255, 255,   0,  10, 217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215,   9,   0, 255, 255;
				 255, 255,  12, 106, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 103,  14, 255, 255;
				 255,   0,   9, 225, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224,   8,   0, 255;
				 255,   2,  78, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  77,   2, 255;
				 255,  17, 178, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 176,  17, 255;
				   0,   8, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248,   8,   0;
				   0,  64, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 243, 255,  60,   0;
				  10, 132, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 190, 110, 132, 255, 131,  10;
				  19, 174, 255, 176,  34,  34,  92, 119, 119, 119, 240,  97,  54,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  85,  75,  77, 246, 150, 255, 171,  20;
				  14, 211, 255, 249,  30,   0,  91, 255, 255, 255, 210,   1, 173, 255, 255, 255, 255, 255,  94, 107, 255, 158, 162, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213, 120, 133, 255, 209,  14;
				   8, 229, 255, 255, 148,   0,   3, 218, 255, 255,  87,  44, 253, 255, 255, 255, 255, 255,  35,  54, 255,  64,  81, 255, 255, 255, 255, 255, 255, 255, 231, 122, 193, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 255, 227,   9;
				   4, 241, 255, 255, 247,  25,   0,  97, 255, 215,   2, 148, 170, 219, 255, 184, 186, 255,  35,  54, 255, 181, 188, 255, 177, 212, 194, 158, 235, 255, 125,   0, 110, 209, 211, 170, 244, 244, 170, 211, 255, 226, 158, 166, 240, 255, 240,   4;
				   4, 241, 255, 255, 255, 141,   0,   5, 222,  92,  40, 195,   0, 146, 255,  40,  48, 255,  35,  54, 255,  34,  53, 255,  25,  26,   2,   0,  45, 255,  22,   0,  11, 127, 122,   0, 221, 221,   0, 122, 226,  13,  40,  41, 212, 255, 240,   4;
				   8, 229, 255, 255, 255, 244,  21,   0,  72,   3, 162, 198,   0, 145, 255,  39,  47, 255,  35,  54, 255,  34,  53, 255,  27,  32, 247,  98,   0, 227, 186,   0, 165, 255, 124,   0, 221, 220,   0, 122, 185,   0,  90, 229, 255, 255, 227,   9;
				  14, 211, 255, 255, 255, 255, 135,   0,   0,  35, 251, 201,   0, 142, 255,  37,  46, 255,  35,  54, 255,  34,  53, 255,  28,  58, 255, 128,   0, 214, 188,   0, 164, 255, 130,   0, 218, 219,   0, 121, 252, 116,  10,  11, 197, 255, 209,  14;
				  19, 173, 255, 255, 255, 255, 242,  18,   0, 156, 255, 217,   0,  68, 172,   8,  44, 255,  35,  54, 255,  34,  53, 255,  29,  58, 255, 130,   0, 212, 198,   0,  98, 221, 146,   0, 125, 124,   0, 119, 233, 206, 184,   0, 125, 255, 171,  20;
				  10, 132, 255, 255, 255, 255, 255, 129,  30, 250, 255, 255,  83,   0,  30,  59,  41, 255,  35,  54, 255,  34,  53, 255,  30,  59, 255, 131,   0, 212, 249,  50,   0, 127, 230,  34,   0,  71,  16, 116, 173,   3,   0,  36, 216, 255, 131,  10;
				   0,  62, 255, 255, 255, 255, 255, 245, 224, 255, 255, 255, 255, 235, 251, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 235, 254, 255, 253, 234, 255, 255, 255, 255, 246, 227, 255, 255, 255,  59,   0;
				   0,   8, 249, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248,   7,   0;
				 255,  17, 177, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 175,  17, 255;
				 255,   2,  77, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  76,   2, 255;
				 255,   0,   8, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223,   9,   0, 255;
				 255, 255,  12, 103, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 101,  12, 255, 255;
				 255, 255,   0,   9, 214, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,   9,   0, 255, 255;
				 255, 255, 255,   6,  59, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,  57,   6, 255, 255, 255;
				 255, 255, 255,   0,  14, 141, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 140,  14,   0, 255, 255, 255;
				 255, 255, 255, 255,   0,  10, 198, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 196,   9,   0, 255, 255, 255, 255;
				 255, 255, 255, 255, 255,   3,  15, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 214,  15,   0, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255,   5,  22, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 214,  21,   5, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255,   5,  15, 197, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 196,  15,   5, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255,   3,  10, 142, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 140,   9,   0, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  14,  59, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,  57,  14,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   6,   9, 103, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223, 101,   9,   6,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,  12,   8,  76, 176, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 175,  75,   9,  12,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   2,  17,   8,  61, 132, 172, 210, 227, 239, 239, 227, 209, 171, 131,  60,   7,  17,   2,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255;
				 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,   0,   0,  10,  20,  16,   8,   4,   4,   9,  16,  20,  10,   0,   0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255];
alpha_map = [	   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  24,  88, 148, 198, 230, 245, 252, 252, 245, 230, 197, 148,  87,  23,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  19, 110, 215, 250, 242, 254, 255, 255, 255, 255, 255, 255, 255, 255, 254, 241, 250, 214, 109,  18,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  27, 150, 247, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244, 246, 148,  26,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   5, 123, 246, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 246, 120,   5,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,  39, 219, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244, 217,  37,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,  84, 245, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 245,  81,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0, 106, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 247, 104,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0, 105, 245, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 246, 104,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,  83, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 247,  80,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,  39, 245, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 245,  37,   0,   0,   0,   0;
				   0,   0,   0,   6, 219, 252, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 218,   5,   0,   0,   0;
				   0,   0,   0, 122, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 245, 122,   0,   0,   0;
				   0,   0,  27, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 246,  26,   0,   0;
				   0,   0, 149, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 249, 149,   0,   0;
				   0,  19, 247, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 246,  18,   0;
				   0, 110, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 245, 108,   0;
				   0, 215, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 213,   0;
				  24, 249, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 250,  22;
				  88, 242, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 241,  86;
				 149, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 148;
				 198, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 195;
				 232, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 230;
				 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 243;
				 252, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 251;
				 252, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 251;
				 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 243;
				 231, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 230;
				 197, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 195;
				 148, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 147;
				  88, 241, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 241,  85;
				  23, 250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 250,  21;
				   0, 214, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 211,   0;
				   0, 108, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 245, 107,   0;
				   0,  18, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 246,  18,   0;
				   0,   0, 148, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 145,   0,   0;
				   0,   0,  26, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 245,  24,   0,   0;
				   0,   0,   0, 120, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244, 118,   0,   0,   0;
				   0,   0,   0,   5, 217, 252, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 216,   5,   0,   0,   0;
				   0,   0,   0,   0,  37, 245, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244,  36,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,  82, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 246,  78,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0, 104, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 245, 103,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0, 104, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 247, 103,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,  81, 245, 252, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 244,  78,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,  38, 218, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244, 216,  36,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   5, 121, 246, 248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 245, 118,   5,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  26, 148, 246, 244, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244, 246, 145,  24,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  18, 108, 213, 250, 241, 254, 255, 255, 255, 255, 255, 255, 255, 255, 254, 241, 250, 211, 107,  17,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0;
				   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  22,  86, 147, 196, 229, 244, 252, 252, 244, 229, 196, 146,  86,  21,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0];
varargout = {alpha_map};


%% ************************************************************************
function usb_pid_list = Vulintus_USB_VID_PID_List

%Vulintus_USB_VID_PID_List.m - Vulintus, Inc.
%
%   VULINTUS_USB_VID_PID_LIST returns a cell array with USB vendor ID (VID) 
%   and product ID (PID) numbers assigned to Vulintus devices
%
%   UPDATE LOG:
%   	2024-02-22 - Drew Sloan - Function first created.
%		2025-01-01 - Drew Sloan - Added pellet dispenser.
%

usb_pid_list = {
    '04D8',     'E6C2',     'HabiTrak Thermal Activity Monitor';
    '0403',     '6A21',     'MotoTrak Pellet Pedestal Module';	
	'04D8',     'E59E',     'MotoTrak Spherical Treadmill Module';
    '04D8',     'E6C3',     'OmniTrak Common Controller';
    '0403',     '6A20',     'OmniTrak Nosepoke Module';
	'0403', 	'6A26', 	'OmniTrak Pocket Door Module';
	'04D8',     'E52F',     'OmniTrak Social Choice Module';
    '0403',     '6A24',     'OmniTrak Three-Nosepoke Module';
	'0403',     '6A23',     'SensiTrak Arm Proprioception Module';
	'0403',     '6A22',     'SensiTrak Tactile Carousel Module';
	'0403',     '6A25',     'SensiTrak Vibrotactile Module';
	'04D8',     'E6AC',     'VPB Linear Autopositioner';
	'04D8',     'E62E',     'VPB Liquid Dispenser';
	'04D8',	 	'E530',     'VPB Pellet Dispenser';
	'04D8',     'E6C0',     'VPB Ring Light';	
};


%% ************************************************************************
function Vulintus_Check_Required_Classes(req_class_files)

%
%Vulintus_Check_Required_Classes.m - Vulintus, Inc.
%
%   VULINTUS_CHECK_REQUIRED_CLASSES checks to see if the specified classes
%   are in the MATLAB search path. If they're not found, it will create
%   them from programmatically generated scripts and add them to the search
%   path.
%   
%   UPDATE LOG:
%   2024-07-09 - Drew Sloan - Function first created.
%


if ~iscell(req_class_files)                                                 %If the input isn't a cell array.
    req_class_files = {req_class_files};                                    %Put it inside a cell array.
end

class_path = userpath;                                                      %Grab the MATLAB user-path.
if isempty(class_path)                                                      %If no user-path was returned.
    userpath('reset');                                                      %Reset the user-path to the default.
    class_path = userpath;                                                  %Grab the MATLAB user-path.
end
if ~contains(path, class_path)                                              %If the class path isn't in the search path...
    addpath(class_path);                                                    %Add the class path to the search path.
end

for i = 1:length(req_class_files)                                           %Step through each required class.
    class_files = which(req_class_files{i},'-all');                         %Check to see if the class exists on the search path.    
    if length(class_files) > 1                                              %If there's more than one match...
        delete_copy = startsWith(class_files,class_path);                   %Find the copies in the user path.
        for j = 1:length(delete_copy)                                       %Step through each copy.            
            if delete_copy(j) == true                                       %If the copy is in the user path...
                delete(class_files{j})                                      %Delete the copy in the user path.
            end
        end
        class_files = which(req_class_files{i},'-all');                     %Check again to see if the class exists on the search path.
    end
    collated_txt = Vulintus_Load_Class_File_Text(req_class_files{i});       %Grab the text collated into the larger file.
    if isempty(class_files)                                                 %If the classes weren't found...
        filename = fullfile(class_path,[req_class_files{i} '.m']);          %Set the filename.
        Vulintus_Cell_to_Text_File(collated_txt,filename);                  %Overwrite the existing class with the collated text.
    else                                                                    %Otherwise, if the classes were found...
        existing_txt = Vulintus_Text_File_To_Cell(class_files{1});          %Grab the existing text of the class definition.
        
        if ~isequal(existing_txt,collated_txt)                              %If the text doesn't match...
            if startsWith(class_files{1},class_path)                        %If the class is in the user path...
                Vulintus_Cell_to_Text_File(collated_txt,class_files{1});    %Overwrite the existing class with the collated text.
            else                                                            %Otherwise...
                warning(['WARNING IN %s: Class ''%s'' appears to be '...
                    'out of date!'], upper(mfilename),req_class_files{i});  %Show a warning.
            end
        end
    end
end


%% ************************************************************************
function Vulintus_Cell_to_Text_File(txt,file)

%
%Vulintus_Cell_to_Text_File.m - Vulintus, Inc.
%
%   VULINTUS_CELL_TO_TEXT_FILE takes a cell array of text and writes it
%   into the specified file, with each cell corresponding to a line of
%   text.
%   
%   UPDATE LOG:
%   2024-07-09 - Drew Sloan - Function first created.
%


[fid, errmsg] = fopen(file,'wt');                                           %Open the specified script for writing as text.
if fid == -1                                                                %If the file could not be opened...
    warning(['ERROR IN %s: Could not open the specified file!\n\t"%s"'...
        '\n\tERROR: %s'],upper(mfilename),file,errmsg);                     %Show a warning.
    close(fid);                                                             %Close the file.
    return                                                                  %Skip execution of the rest of the function.
end

for i = 1:length(txt)                                                       %Step through each line of text.
    % txt{i} = strrep(txt{i},'''','''''');                                    %Replace each apostrophe with double apostrophes.    
    fprintf(fid,'%s\n',txt{i});                                             %Print each line of text to the file.
end
fclose(fid);                                                                %Close the configuration file.


%% ************************************************************************
function txt_cell = Vulintus_Text_File_To_Cell(file)

%
%Vulintus_Text_File_To_Cell.m - Vulintus, Inc.
%
%   VULINTUS_TEXT_FILE_TO_CELL reads in a plain text file and returns the
%   text as a cell array with cells corresponding to the lines of text.
%   
%   UPDATE LOG:
%   2024-07-09 - Drew Sloan - Function first created.
%


if ~exist(file,'file')                                                      %If the specified file doesn't exist...
    error('ERROR IN %s: Specified file doesn''t exist!\n\t"%s"',...
            upper(mfilename),v);                                            %Show an error.
end

[fid, errmsg] = fopen(file,'rt');                                           %Open the specified script for reading as text.
if fid == -1                                                                %If the file could not be opened...
    warning(['ERROR IN %s: Could not open the specified file!\n\t"%s"'...
        '\n\tERROR: %s'],upper(mfilename),file,errmsg);                     %Show a warning.
    close(fid);                                                             %Close the file.
    return                                                                  %Skip execution of the rest of the function.
end
txt = fread(fid,'*char')';                                                  %Read in the file data as text.
fclose(fid);                                                                %Close the configuration file.
nl = find(txt == newline);                                                  %Find all new lines in the string.
nl = [0, nl, length(txt)+1];                                                %Add indices for the first and last elements of the string.
txt_cell = cell(length(nl)-1,1);                                            %Create a cell array to hold the text.
for i = 2:length(nl)                                                        %Step through each entry in the string.
    txt_cell{i-1} = txt((nl(i-1)+1):(nl(i)-1));                             %Grab the line of text.
    if isempty(txt_cell{i-1})                                               %If the cell is empty...
        txt_cell{i-1} = '';                                                 %Make sure it's a uniform kind of empty.
    end
end
keepers = ~cellfun(@isempty,txt_cell);                                      %Find all non-empty lines.
i = find(keepers == 1,1,'last');                                            %Find the last non-empty line.
txt_cell(i+1:end) = [];                                                     %Kick out any empty lines at the end.


%% ************************************************************************
function txt = Vulintus_Load_Class_File_Text(class_file_name)

%Programmatically generated: 2025-06-19, 12:55:02

switch class_file_name

	case 'Vulintus_OTSC_Stream_Class'
		txt =	{
			'classdef Vulintus_OTSC_Stream_Class < handle';
			'';
			'%';
			'% Vulintus_OTSC_Stream_Class.m';
			'% ';
			'%   copyright 2025, Vulintus, Inc.';
			'%';
			'%   VULINTUS_OTSC_STREAM_CLASS is a persistent handle class for processing';
			'%   incoming serial data from a Vulintus OmniTrak device that is';
			'%   communicating using the OmniTrak Serial Communication (OTSC) protocol.';
			'%   The OTSC protocol used by this class, and all Vulintus OmniTrak ';
			'%   devices, is open-source and available here:';
			'%';
			'%       https://github.com/Vulintus/OmniTrak_Serial_Communication';
			'%   ';
			'%   UPDATE LOG:';
			'%   2025-04-09 - Drew Sloan - Moved the functions of the "stream" field';
			'%                             created by Connect_OmniTrak to this class.';
			'%   2025-05-21 - Drew Sloan - Added a clear function to clear the buffers.';
			'%';
			'';
			'    %Public properties.';
			'    properties (Access = public, SetObservable)                        ';
			'        ';
			'        verbose logical = false;                                            %Control printing to the command line of received packets.';
			'        fcn dictionary = dictionary;                                        %Dictionary of functions to execute when a packet is received.';
			'        sources (:,1) double = 0;                                           %List the source indices.';
			'        use_interrupt logical = false;                                      %Flag for using the serial BytesAvailable interrupt function.';
			'        serialcon;                                                          %Serialport connection handle.';
			'';
			'    end';
			'';
			'    %Read-only properties.';
			'    properties (GetAccess = public, SetAccess = private, SetObservable)       ';
			'';
			'        buffer dictionary = dictionary;                                     %Serial input buffers.';
			'        active logical = false;                                             %Flag for when streaming data is enabled.';
			'        ';
			'    end';
			'    ';
			'    %Public read-only properties set in the constructor.';
			'    properties (GetAccess = public, SetAccess = immutable)                          ';
			'        ';
			'        period struct = struct(''set'', [], ''get'', []);                       %Function handle structure for the streaming period set/get functions.        ';
			'        otsc_codes dictionary = dictionary;                                 %Dictionary of OTSC codes and definition names.';
			'        packet_info dictionary = dictionary;                                %Dictionary of OTSC packet specifications.';
			'        serial_read function_handle;                                        %Serial read function handle.';
			'        serial_num_bytes function_handle;                                   %Serial bytes available function handle.';
			'        ';
			'    end';
			'';
			'    %Private properties.';
			'    properties (Access = private)                                           ';
			'        ';
			'        pass_up_cmd double;                                                 %OTSC code for data passed through the controller.';
			'        prev_code dictionary = dictionary;                                  %Previous block codes.';
			'';
			'    end';
			'';
			'    %Private read-only properties set in the constructor.';
			'    properties (GetAccess = private, SetAccess = immutable)                                           ';
			'';
			'    end';
			'    ';
			'';
			'    %Visible public methods.';
			'    methods (Access = public)';
			'';
			'        % Class constructor.';
			'        function stream = Vulintus_OTSC_Stream_Class(serialcon, varargin)';
			'            ';
			'            if nargin > 1                                                   %If the OTSC codes were passed...';
			'                stream.otsc_codes = varargin{1};                            %Grab the OTSC codes.';
			'            else                                                            %Otherwise...';
			'                stream.otsc_codes = Vulintus_Load_OTSC_Codes;               %Load the OTSC codes.';
			'            end            ';
			'            [~, stream.pass_up_cmd] = Vulintus_OTSC_Passthrough_Commands;   %Grab the passthrough upstream command.';
			'            ';
			'            stream.serialcon = serialcon;                                   %Save the serial connection handle to the class.';
			'            switch class(stream.serialcon)                                  %Switch between the types of serial connections.';
			'                case ''internal.Serialport''                                  %Newer serialport functions.';
			'                    stream.serial_num_bytes = @serialcon.NumBytesAvailable; %Number of bytes available.';
			'                    stream.serial_read = ...';
			'                        @(count)read(serialcon,count,''uint8'');              %Read data from the serialport object.            ';
			'                case ''serial''                                               %Older, deprecated serial functions.';
			'                    stream.serial_num_bytes = @serialcon.BytesAvailable;    %Number of bytes available.';
			'                    stream.serial_read = ...';
			'                        @(count)fread(serialcon,count,''uint8'');             %Read data from the serialport object.';
			'            end';
			'';
			'            stream.packet_info = Vulintus_Load_OTSC_Packet_Info;            %Load the OTSC packet specifications.';
			'            pkt_keys = keys(stream.packet_info);                            %Grab the packet specification dictionary keys.';
			'            for i = 1:length(pkt_keys)                                      %Step through all of the keys.            ';
			'                code_name = stream.packet_info(pkt_keys(i)).name;           %Grab the code name.';
			'                stream.fcn(code_name) = ...';
			'                    @(varargin)Vulintus_OTSC_Empty_Process(code_name,...';
			'                    varargin{:});                                           %Create an empty cell to hold the process function for each code.';
			'            end';
			'            ';
			'            stream.period.get = ...';
			'                @(varargin)Vulintus_OTSC_Transaction(serialcon,...';
			'	            stream.otsc_codes(''REQ_STREAM_PERIOD''),...';
			'                ''reply'',{1,''uint32''},...';
			'                varargin{:});                                               %Streaming period set function (in microseconds).   ';
			'            stream.period.set = ...';
			'                @(period,varargin)Vulintus_OTSC_Transaction(serialcon,...';
			'                stream.otsc_codes(''STREAM_PERIOD''),...';
			'                ''data'',{period,''uint32''},...';
			'                varargin{:});                                               %Streaming period request function (in microseconds).';
			'            ';
			'            stream.buffer(0) = Vulintus_FIFO_Buffer(''uint8'',4096);          %Create a new Vulintus buffer instance for the primary device.';
			'            stream.buffer(0).waiting_for = 2;                               %Set the ready flag threshold on the primary buffer to 2 bytes.';
			'            stream.prev_code(0) = 0;                                        %Initialize the previous block code tracking dictionary.';
			'';
			'            % addlistener(stream,''fcn'',''PostSet'',...';
			'            %     @Vulintus_OTSC_Stream_Class.Property_Change_Listener);      %Add a listener for changes to the process functions.';
			'            addlistener(stream,''sources'',''PostSet'',...';
			'                @Vulintus_OTSC_Stream_Class.Property_Change_Listener);      %Add a listener for changes to the sources.';
			'';
			'        end';
			'        ';
			'        %Enable/disable streaming on the specified device.';
			'        function enable(stream, enable_val, varargin)';
			'            Vulintus_OTSC_Transaction(stream.serialcon,...';
			'                stream.otsc_codes(''STREAM_ENABLE''),...';
			'                ''data'',{enable_val,''uint8''},...';
			'                varargin{:});                                               %Send the stream enable/disable command.';
			'            if enable_val > 0                                               %If streaming is being enabled...';
			'                if ~stream.active && stream.use_interrupt                   %If streaming wasn''t previously active...';
			'                    stream.Set_Serial_Callback(2);                          %Set the BytesAvailable function.';
			'                end';
			'                stream.active = true;                                       %Set the active streaming flag to true.';
			'            else                                                            %Otherwise, if streaming is being disabled...';
			'                passthrough = false;                                        %Assume the command isn''t a passthrough by default.';
			'                for i = 1:length(varargin)                                  %Step through the optional inputs';
			'                    if ischar(varargin{i}) && ...';
			'                            strcmpi(varargin{i},''pasthrough'')               %If the passthrough option was specified...';
			'                        passthrough = true;                                 %Indicate that this is a passthrough command.';
			'                    end';
			'                end';
			'                if ~passthrough                                             %If streaming was disabled on the primary device...';
			'                    stream.active = false;                                  %Set the active streaming flag to true.';
			'                    stream.Clear_Serial_Callback();                         %Clear the serial callback.';
			'                end';
			'            end';
			'        end';
			'';
			'        %Process any incoming serial bytes.';
			'        function n_bytes = read(stream, varargin)';
			'            n_bytes = stream.serial_num_bytes();                            %Grab the number of available bytes.';
			'            if n_bytes > 0                                                  %If there''s bytes available on the serial connection.';
			'                stream.buffer(0).write(stream.serial_read(n_bytes));        %Copy the bytes to the primary buffer.';
			'                for i = 1:length(stream.sources)                            %Step through each data source (i.e. device).';
			'                    stream.Process_Buffer(stream.sources(i));               %Go through each buffer and process any complete packets.';
			'                end';
			'            end';
			'            if nargin > 1                                                   %If the user specified a pause duration...';
			'                pause(varargin{1});                                         %Pause for the specified duration.';
			'                drawnow;                                                    %Flush the event queue.';
			'            end';
			'        end';
			'';
			'        %Clear any bytes currently in the serial buffers.';
			'        function clear(stream)';
			'            for i = 1:length(stream.sources)                                %Step through the data sources.';
			'                stream.buffer(stream.sources(i)).clear();                   %Clear the buffer.';
			'                stream.buffer(stream.sources(i)).waiting_for = 2;           %Set the ready flag threshold to 2 bytes.';
			'            end';
			'        end';
			'';
			'    end';
			'';
			'    ';
			'    %Hidden public methods.';
			'    methods (Access = public, Hidden)';
			'';
			'        %Process any incoming serial bytes.';
			'        function Serial_Interrupt(stream, ~, ~)';
			'            n_bytes = stream.read();                                        %Read and process any new bytes.';
			'            if n_bytes > 0                                                  %If new bytes were received...';
			'                n_bytes = min(stream.buffer(0).waiting_for, 256);           %Set the bytes required to trigger the BytesAvailable function.';
			'                stream.Set_Serial_Callback(n_bytes);                        %Update the bytes required to trigger the BytesAvailable function.';
			'            end';
			'        end';
			'';
			'    end';
			'';
			'';
			'    %Private methods.';
			'    methods (Access = private)';
			'';
			'        %Initialize the data buffers for the listed sources.';
			'        function Initialize_Buffers(stream)';
			'            if ~any(stream.sources == 0)                                    %If the primary device index isn''t included in the current source list.';
			'                stream.sources = [0; stream.sources];                       %Add the a zero index as the first source.';
			'                return                                                      %Skip the rest of the function.';
			'            end';
			'            old_sources = keys(stream.buffer);                              %Grab the keys for current buffers.';
			'            for i = 1:length(old_sources)                                   %Step through the current buffers.';
			'                if ~any(old_sources(i) == stream.sources)                   %If any existing buffer no longer has a source...';
			'                    remove(stream.buffer, old_sources(i));                  %Delete the now-obsolete buffer.';
			'                    remove(stream.prev_code, old_sources(i));               %Delete the now-obsolete previous block code entry.';
			'                end';
			'            end';
			'            for i = 1:length(stream.sources)                                %Step through the data sources.';
			'                if ~isKey(stream.buffer, stream.sources(i))                 %If there''s no buffer entry for this source.';
			'                    stream.buffer(stream.sources(i)) = ...';
			'                        Vulintus_FIFO_Buffer(''uint8'',4096);                 %Initialize a new buffer class for this source.';
			'                    stream.buffer(stream.sources(i)).waiting_for = 2;       %Set the ready flag threshold to 2 bytes.';
			'                    stream.prev_code(stream.sources(i)) = 0;                %Set each previous block code to zero.';
			'                end';
			'            end';
			'        end';
			'        ';
			'        %Process any available, complete data packets in the buffers.';
			'        function Process_Buffer(stream, src)';
			'            while stream.buffer(src).ready                                  %Loop through all complete packets.';
			'                code = stream.buffer(src).peek(1,''uint16'');                 %Grab the OTSC code.';
			'                if code == stream.pass_up_cmd                               %If the code is for an passthrough upstream packet...';
			'                    if stream.buffer(src).count < 5                         %If the buffer doesn''t have at least 5 bytes in it.';
			'                        stream.buffer(src).waiting_for = 5;                 %Update the number of bytes we''re waiting for in the buffer.';
			'                        return                                              %Skip the rest of the function.';
			'                    end';
			'                    temp_buffer = stream.buffer(src).peek(5);               %Grab the first 5 bytes.';
			'                    N = typecast(temp_buffer(4:5),''uint16'');                %Grab the bytes-to-follow count.';
			'                    if stream.buffer(src).count < (5 + N)                   %If the buffer doesn''t have all the bytes in it yet...';
			'                        stream.buffer(src).waiting_for = (5 + N);           %Update the number of bytes we''re waiting for in the buffer.';
			'                        return                                              %Skip the rest of the function.';
			'                    end';
			'                    stream.buffer(src).clear(5);                            %Clear out the first five bytes.';
			'                    i = temp_buffer(3);                                     %Grab the source index.';
			'                    stream.buffer(i).write(stream.buffer(src).read(N));     %Copy the bytes over to the buffer for the passthrough source.';
			'                    stream.buffer(src).waiting_for = 2;                     %Reset the number of bytes we''re waiting for to 2 (OTSC code size).';
			'                    stream.prev_code(src) = code;                           %Save the current code for debugging purposes.';
			'                    continue';
			'                elseif ~isKey(stream.packet_info, code)                     %If this code isn''t in the packet specifications...';
			'                    lookup_table = entries(stream.otsc_codes);              %Convert the OTSC code dictionary to a lookup table.';
			'                    match_index = (code == lookup_table{:,2});              %Check to see if the code matches any value in the lookup table.';
			'                    if ~any(match_index)                                    %If there is no match...';
			'                        stream.enable(0);                                   %Disable streaming on all devices.';
			'                        error([''ERROR IN %s: Unknown OTSC block ''...';
			'                            ''code 0x%04X received from Device %1.0f!''...';
			'                            ''\n\tPreceding block code was 0x%04X, ''...';
			'                            ''buffer count is %1.0f samples.''],...';
			'                            upper(mfilename), code, src,...';
			'                            stream.prev_code(src),...';
			'                            stream.buffer(src).count);                      %Throw an error.';
			'                    else                                                    %Otherwise, if there is a match...';
			'                        codename = lookup_table{match_index, 1};            %Grab the packet name.';
			'                        if strcmpi(codename,''UNKNOWN_BLOCK_ERROR'')          %If the code was for an unknown block error...';
			'                            code = typecast(stream.buffer(src).peek(4),...';
			'                                ''uint16'');                                  %Grab the unknown block code.';
			'                            warning([''%s - Device %1.0f reported an ''...';
			'                                ''unknown block error for OTSC block ''...';
			'                                ''value 0x%04X.''],...';
			'                                upper(mfilename), src, code(2));            %Show a warning message.';
			'                        else                                                %Otherwise...';
			'                            error([''ERROR IN %s: Need to finish coding ''...';
			'                                ''for packet type ''''%s'''' (0x%04X) ''...';
			'                                ''received from Device %1.0f!''...';
			'                                ''\n\tPreceding block code was 0x%04X, ''...';
			'                                ''buffer count is %1.0f samples.''],...';
			'                                upper(mfilename), codename, code, src,...';
			'                                stream.prev_code(src),...';
			'                                stream.buffer(src).count);                  %Throw an error.';
			'                        end       ';
			'                    end';
			'                    stream.prev_code(src) = code;                           %Save the current code for debugging purposes.';
			'                    continue                                                %Skip to the next instance.';
			'                end                ';
			'                if stream.verbose                                           %If verbose outputs are turned on.';
			'                    fprintf(1,''OTSC RECEIVED [%1.0f]: %s (0x%04X)\n'',...';
			'                        src, stream.packet_info(code).name, code);          %Print the received packet name and source to the command line.';
			'                end';
			'                bytes_required = ...';
			'                    Vulintus_OTSC_Parse_Packet(stream.buffer(src),...';
			'                    src, stream.packet_info(code),...';
			'                    stream.fcn(stream.packet_info(code).name));             %Call the assigned parsing function.';
			'                if bytes_required > 0                                       %If further bytes are required to complete the packet...';
			'                    stream.buffer(src).waiting_for = bytes_required;        %Update the number of bytes we''re waiting for in the buffer.';
			'                else                                                        %Otherwise...';
			'                    stream.buffer(src).waiting_for = 2;                     %Reset the number of bytes we''re waiting for to 2 (OTSC code size).';
			'                end';
			'                stream.prev_code(src) = code;                               %Save the current code for debugging purposes.';
			'            end';
			'';
			'        end';
			'        ';
			'        %Set the serial "BytesAvailable" function.';
			'        function Set_Serial_Callback(stream, n_bytes)';
			'            switch class(stream.serialcon)                                  %Switch between the types of serial connections.';
			'                case ''internal.Serialport''                                  %Newer serialport functions.';
			'                    configureCallback(stream.serialcon,''byte'', n_bytes,...';
			'                        @(obj,event)stream.Serial_Interrupt(obj,event));    %Set the BytesAvailable function.';
			'                case ''serial''                                               %Older, deprecated serial functions.';
			'                    if isempty(stream.serialcon.BytesAvailableFcn)          %If the BytesAvailable function isn''t yet set...';
			'                        stream.serialcon.BytesAvailableFcn = ...';
			'                            @(obj,event)stream.Serial_Interrupt(obj,event); %Set the BytesAvailable function.';
			'                        stream.serialcon.BytesAvailableFcnMode = ...';
			'                            ''byte'';                                         %Set the BytesAvailable function mode.';
			'                    end';
			'                    stream.serialcon.BytesAvailableFcnCount = n_bytes;      %Set the BytesAvailable function byte count.';
			'            end';
			'        end';
			'';
			'        %Clear the serial "BytesAvailable function.';
			'        function Clear_Serial_Callback(stream)';
			'            switch class(stream.serialcon)                                  %Switch between the types of serial connections.';
			'                case ''internal.Serialport''                                  %Newer serialport functions.';
			'                    configureCallback(stream.serialcon,''off'');              %Disable the serial BytesAvailable function.';
			'                case ''serial''                                               %Older, deprecated serial functions.';
			'                    stream.serialcon.BytesAvailableFcn = '''';                %Disable the serial BytesAvailable function.';
			'            end';
			'        end';
			'';
			'    end';
			'';
			'';
			'    %Static, hidden methods.';
			'    methods (Static, Hidden)';
			'        ';
			'        %Executes when a monitored class property is changed.';
			'        function Property_Change_Listener(src,event)';
			'            switch src.Name                                                 %Switch between the monitored properties.';
			'                case ''sources''                                              %Data sources list.';
			'                    event.AffectedObject.Initialize_Buffers();              %Update the process functions in the handler dictionary.';
			'            end';
			'        end';
			'';
			'    end';
			'';
			'end';
		};

	case 'Vulintus_FIFO_Buffer'
		txt =	{
			'classdef Vulintus_FIFO_Buffer < handle';
			'';
			'%';
			'% Vulintus_FIFO_Buffer.m';
			'%';
			'%   VULINTUS_FIFO_BUFFER is a persistent handle class for a First-In / ';
			'%   First-Out (FIFO) buffer, used most often in Vulintus code to buffer';
			'%   incoming serial data.';
			'%   ';
			'%   UPDATE LOG:';
			'%   2025-04-09 - Drew Sloan - Moved the functions of the "stream" field';
			'%                             created by Connect_OmniTrak to this class.';
			'%';
			'';
			'';
			'    %Public properties.';
			'    properties (Access = public, SetObservable)                        ';
			'        ';
			'        waiting_for double = 1;                                             %Allow the user to set a target number of values to flag.';
			'';
			'    end';
			'';
			'    %Read-only public properties.';
			'    properties (GetAccess = public, SetAccess = private, SetObservable)               ';
			'        ';
			'        size uint32 = [1, 100];                                             %Current buffer size.';
			'        count double = 0;                                                   %Current buffer byte count.     ';
			'        type char = ''double'';                                               %Class of values in the buffer.';
			'        ready logical = false;                                              %Flag when the buffer has received a specified number of bytes.';
			'        ';
			'    end';
			'    ';
			'    %Private properties.';
			'    properties (Access = private)                                           ';
			'        ';
			'        values;                                                             %The array that will hold the values (we won''t define a type yet).';
			'        classes = {''single'', ''double'',...';
			'                ''int8'', ''int16'', ''int32'', ''int64'',...';
			'                ''uint8'', ''uint16'', ''uint32'', ''uint64'',...';
			'                ''logical'',...';
			'                ''char''};                                                    %List the recognized classes.';
			'';
			'    end';
			'';
			'';
			'    %Public methods.';
			'    methods (Access = public)';
			'';
			'        % Class constructor.';
			'        function buffer = Vulintus_FIFO_Buffer(varargin)';
			'            for i = 1:length(varargin)                                      %Step through the optional inputs.';
			'                if ischar(varargin{i}) && ...';
			'                        any(strcmpi(varargin{i},buffer.classes))            %If the input is a character array.';
			'                    buffer.type = lower(varargin{i});                       %Set the data type.';
			'                elseif isscalar(varargin{i})                                %If the input is a single number.';
			'                    buffer.size(2) = uint32(varargin{i});                   %Set the buffer size.';
			'                elseif length(varargin{i}) == 2                             %If two values were passed.';
			'                    buffer.size(:) = uint32(varargin{i}(:));                %Set the buffer to the specified size.';
			'                else                                                        %Otherwise...                   ';
			'                    error([''ERROR IN %s: Input arguments should be ''...';
			'                        ''either a data class (i.e. ''''uint8'''', ''...';
			'                        ''''''uint16'''', etc.) or the initial buffer size ''...';
			'                        ''specified as numeric values!''],...';
			'                        upper(mfilename));                                  %Throw an error.';
			'                end';
			'            end';
			'            ';
			'            buffer.values = cast(zeros(buffer.size),buffer.type);           %Create the array to hold the buffer values.';
			'';
			'            addlistener(buffer,''waiting_for'',''PostSet'',...';
			'                @Vulintus_FIFO_Buffer.Property_Change_Listener);           %Add a listener for changes in the "waiting for" count.';
			'';
			'        end';
			'        ';
			'        %Write data to the buffer.';
			'        function write(buffer, data)';
			'            % validateattributes(data,{''numeric''},...';
			'            %         {''nrows'', buffer.size(1)}, mfilename);                  %Validate the data size.';
			'            N = size(data,2);                                               %#ok<CPROPLC> %Grab the number of columns.';
			'            i = buffer.count + (1:N);                                       %Set the new buffer indices.';
			'            buffer.values(:,i) = data;                                      %Copy the data into the buffer.';
			'            buffer.count = i(end);                                          %Update the buffer count.';
			'            if i(end) > buffer.size                                         %If the buffer had to expand...';
			'                buffer.size(2) = i(end);                                    %Set the new buffer size.';
			'            end';
			'            buffer.Update_Ready_Flag();                                     %Update the ready flag.';
			'        end';
			'';
			'        %Clear values from the buffer.';
			'        function clear(buffer, varargin)';
			'            n_values = buffer.count;                                        %Assume we''ll clear out the whole buffer.';
			'            if nargin > 1                                                   %If a count was specified...';
			'                n_values = varargin{1};                                     %Grab the sample count to clear.';
			'                n_values = clip(n_values, 0, buffer.count);                 %Constrain the sample count to the buffer count.';
			'            end';
			'            remaining_count = buffer.count - n_values;                      %Calculate the number of values left.';
			'            if remaining_count                                              %If the entire buffer wasn''t read...';
			'                buffer.values(:,1:remaining_count) = ...';
			'                    buffer.values(:,n_values + (1:remaining_count));        %Shift over the remaining values.';
			'            end';
			'            buffer.count = remaining_count;                                 %Update the buffer count.';
			'            buffer.Update_Ready_Flag();                                     %Update the ready flag.';
			'        end';
			'';
			'        %Read data from the buffer (and remove it).';
			'        function data = read(buffer, varargin)              ';
			'            n_values = buffer.count;                                        %Default to peeking at all the bytes in the buffer.';
			'            out_type = buffer.type;                                         %Assume we want to output the data in the same format as the buffer.';
			'            peek_flag = false;                                              %Assume that we''re clearing the information we''re reading (i.e. not "peeking").';
			'            for i = 1:length(varargin)                                      %Step through the optional input arguments.';
			'                if ischar(varargin{i})                                      %If the argument is a character array.';
			'                    if strcmpi(varargin{i},''peek'')                          %If we''re just peeking at the data...';
			'                        peek_flag = true;                                   %Set the peek flag to true.';
			'                    else                                                    %Otherwise...';
			'                        % validateattributes(varargin{i},buffer.classes,...';
			'                        %     {}, mfilename);                                 %Validate the intput.';
			'                        out_type = varargin{i};                             %Set the output type.';
			'                    end';
			'                else                                                        %Otherwise...';
			'                    % validateattributes(varargin{i},{''numeric''},...';
			'                    %     {''scalar'',''integer'',''nonnegative''}, mfilename);     %Validate the intput.';
			'                    n_values = varargin{i};                                  ';
			'                end';
			'            end';
			'            if ~isequal(out_type, buffer.type)                              %If we''re changing the value type.';
			'                in_size = Vulintus_Return_Data_Type_Size(buffer.type);      %Grab the byte size of the buffer type.';
			'                out_size = Vulintus_Return_Data_Type_Size(out_type);        %Grab the byte size of the output type.                ';
			'                size_ratio = out_size/in_size;                              %Calculate the size ratio.';
			'                n_values = size_ratio*n_values;                             %Scale the number of values to the ratio.';
			'                n_values = min(n_values, buffer.count);                     %Set the number of values to read.';
			'                n_values = n_values - rem(n_values, size_ratio);            %Only return as many values as we can completely return. ';
			'            else                                                            %Otherwise...';
			'                n_values = min(n_values, buffer.count);                     %Set the number of values to read.';
			'            end';
			'            data = buffer.values(:,1:n_values);                             %Return the requested values.';
			'            if ~isequal(out_type, buffer.type)                              %If we''re changing the value type.';
			'                temp_data = ...';
			'                    double(zeros(buffer.size(1),n_values/size_ratio));      %Create a temporary matrix to hold the typecast values.';
			'                for i = 1:buffer.size(1)                                    %Step through each row.';
			'                    temp_data(i,:) = typecast(data(i,:), out_type);         %Cast the data to the requested output type.';
			'                end';
			'                data = cast(temp_data, out_type);                           %Copy the typecast values back to the output array.';
			'            end';
			'            if ~peek_flag                                                   %If we''re reading and not peeking...';
			'                buffer.clear(n_values);                                     %Clear the values that were read out.';
			'            end';
			'        end';
			'';
			'        %Peak at data in the buffer (read without removing it).';
			'        function data = peek(buffer, varargin)';
			'            data = buffer.read(''peek'', varargin{:});                        %Call the read function with the "peek" option.';
			'        end';
			'';
			'    end';
			'    ';
			'    %Private methods.';
			'    methods (Access = private)';
			'        ';
			'        %Update the ready flag based on the count versus the "waiting for" threshold.';
			'        function Update_Ready_Flag(buffer)';
			'            buffer.ready = (buffer.count > buffer.waiting_for);             %Set the flag for if the buffer count exceeds the "waiting for" count.            ';
			'        end';
			'';
			'    end';
			'';
			'    %Static, hidden methods.';
			'    methods (Static, Hidden)';
			'        ';
			'        %Executes when a monitored class property is changed.';
			'        function Property_Change_Listener(src,event)';
			'            switch src.Name                                                 %Switch between the monitored properties.';
			'                case ''waiting_for''                                          %"Waiting for" byte count.';
			'                    event.AffectedObject.Update_Ready_Flag();               %Update the ready flag.';
			'            end';
			'        end';
			'';
			'    end';
			'';
			'end';
		};

	case 'Vulintus_Load_OTSC_Codes'
		txt =	{
			'function serial_codes = Vulintus_Load_OTSC_Codes';
			'';
			'%	Vulintus_Load_OTSC_Codes.m';
			'%';
			'%	copyright, Vulintus, Inc.';
			'%';
			'%	OmniTrak Serial Communication (OTSC) library.';
			'%';
			'%	Library documentation:';
			'%	https://github.com/Vulintus/OmniTrak_Serial_Communication';
			'%';
			'%	This function was programmatically generated: 2025-06-09, 07:45:59 (UTC)';
			'%';
			'';
			'serial_codes = dictionary;';
			'';
			'serial_codes(''CLEAR'') = 0;                               % (0x0000) Reset communication with the device.';
			'serial_codes(''REQ_COMM_VERIFY'') = 1;                     % (0x0001) Request verification that the connected device is using the OTSC serial code library.';
			'serial_codes(''REQ_DEVICE_ID'') = 2;                       % (0x0002) Request the device type ID number.';
			'serial_codes(''DEVICE_ID'') = 3;                           % (0x0003) Set/report the device type ID number.';
			'serial_codes(''REQ_USERSET_ALIAS'') = 4;                   % (0x0004) Request the user-set name for the device.';
			'serial_codes(''USERSET_ALIAS'') = 5;                       % (0x0005) Set/report the user-set name for the device.';
			'serial_codes(''REQ_VULINTUS_ALIAS'') = 6;                  % (0x0006) Request the Vulintus alias (adjective/noun serial number) for the device.';
			'serial_codes(''VULINTUS_ALIAS'') = 7;                      % (0x0007) Set/report the Vulintus alias (adjective/noun serial number) for the device.';
			'serial_codes(''REQ_BOARD_VER'') = 8;                       % (0x0008) Request the circuit board version number.';
			'serial_codes(''BOARD_VER'') = 9;                           % (0x0009) Report the circuit board version number.';
			'serial_codes(''REQ_MAC_ADDR'') = 10;                       % (0x000A) Request the device MAC address.';
			'serial_codes(''MAC_ADDR'') = 11;                           % (0x000B) Report the device MAC address.';
			'serial_codes(''REQ_MCU_SERIALNUM'') = 12;                  % (0x000C) Request the device microcontroller serial number.';
			'serial_codes(''MCU_SERIALNUM'') = 13;                      % (0x000D) Report the device microcontroller serial number.';
			'serial_codes(''REQ_MAX_BAUDRATE'') = 14;                   % (0x000E) Request the maximum serial baud rate for supported by the device, in Hz.';
			'serial_codes(''MAX_BAUDRATE'') = 15;                       % (0x000F) Report the maximum serial baud rate for supported by the device, in Hz.';
			'serial_codes(''SET_BAUDRATE'') = 16;                       % (0x0010) Set the serial baud rate for the OTSC connection to the specified value, in Hz.';
			'serial_codes(''REQ_PROGRAM_MODE'') = 17;                   % (0x0011) Request the current firmware program mode.';
			'serial_codes(''PROGRAM_MODE'') = 18;                       % (0x0012) Set/report the current firmware program mode.';
			'serial_codes(''REQ_MILLIS_MICROS'') = 19;                  % (0x0013) Request the microcontroller''s current millisecond and microsecond clock readings.';
			'serial_codes(''MILLIS_MICROS'') = 20;                      % (0x0014) Report the microcontroller''s current millisecond and microsecond clock readings.';
			'serial_codes(''FW_FILENAME'') = 21;                        % (0x0015) Report the firmware filename.';
			'serial_codes(''REQ_FW_FILENAME'') = 22;                    % (0x0016) Request the firmware filename.';
			'serial_codes(''FW_DATE'') = 23;                            % (0x0017) Report the firmware upload date.';
			'serial_codes(''REQ_FW_DATE'') = 24;                        % (0x0018) Request the firmware upload date.';
			'serial_codes(''FW_TIME'') = 25;                            % (0x0019) Report the firmware upload time.';
			'serial_codes(''REQ_FW_TIME'') = 26;                        % (0x001A) Request the firmware upload time.';
			'';
			'serial_codes(''REQ_LIB_VER'') = 31;                        % (0x001F) Request the OTSC serial code library version.';
			'serial_codes(''LIB_VER'') = 32;                            % (0x0020) Report the OTSC serial code library version.';
			'serial_codes(''UNKNOWN_BLOCK_ERROR'') = 33;                % (0x0021) Indicate an unknown block code error.';
			'serial_codes(''ERROR_INDICATOR'') = 34;                    % (0x0022) Indicate an error and send the associated error code.';
			'serial_codes(''REBOOTING'') = 35;                          % (0x0023) Indicate that the device is rebooting.';
			'';
			'serial_codes(''REQ_CUR_FEEDER'') = 50;                     % (0x0032) Request the current dispenser index.';
			'serial_codes(''CUR_FEEDER'') = 51;                         % (0x0033) Set/report the current dispenser index.';
			'serial_codes(''REQ_FEED_TRIG_DUR'') = 52;                  % (0x0034) Request the current dispenser trigger duration, in milliseconds.';
			'serial_codes(''FEED_TRIG_DUR'') = 53;                      % (0x0035) Set/report the current dispenser trigger duration, in milliseconds.';
			'serial_codes(''TRIGGER_FEEDER'') = 54;                     % (0x0036) Trigger feeding on the currently-selected dispenser.';
			'serial_codes(''STOP_FEED'') = 55;                          % (0x0037) Immediately shut off any active feeding trigger.';
			'serial_codes(''DISPENSE_FIRMWARE'') = 56;                  % (0x0038) Report that a feeding was automatically triggered in the device firmware.';
			'';
			'serial_codes(''POS_ZERO'') = 58;                           % (0x003A) Set the current position as "home" (i.e. zero millimeters/degrees), without doing a homing routine.';
			'serial_codes(''MODULE_REHOME'') = 59;                      % (0x003B) Initiate the homing routine on the module.';
			'serial_codes(''HOMING_COMPLETE'') = 60;                    % (0x003C) Indicate that a module''s homing routine is complete.';
			'serial_codes(''MOVEMENT_START'') = 61;                     % (0x003D) Indicate that a linear/rotary movement has started.';
			'serial_codes(''MOVEMENT_COMPLETE'') = 62;                  % (0x003E) Indicate that a linear/rotary movement is complete.';
			'serial_codes(''MODULE_RETRACT'') = 63;                     % (0x003F) Retract the module movement to it''s starting or base position.';
			'serial_codes(''REQ_TARGET_POS_UNITS'') = 64;               % (0x0040) Request the current target position of a module movement, in millimeters or degrees.';
			'serial_codes(''TARGET_POS_UNITS'') = 65;                   % (0x0041) Set/report the target position of a module movement, in millimeters or degrees.';
			'serial_codes(''REQ_CUR_POS_UNITS'') = 66;                  % (0x0042) Request the current  position of the module movement, in millimeters or degrees.';
			'serial_codes(''CUR_POS_UNITS'') = 67;                      % (0x0043) Set/report the current position of the module movement, in millimeters or degrees.';
			'serial_codes(''REQ_MIN_POS_UNITS'') = 68;                  % (0x0044) Request the current minimum position of a module movement, in millimeters or degrees.';
			'serial_codes(''MIN_POS_UNITS'') = 69;                      % (0x0045) Set/report the current minimum position of a module movement, in millimeters or degrees.';
			'serial_codes(''REQ_MAX_POS_UNITS'') = 70;                  % (0x0046) Request the current maximum position of a module movement, in millimeters or degrees.';
			'serial_codes(''MAX_POS_UNITS'') = 71;                      % (0x0047) Set/report the current maximum position of a module movement, in millimeters or degrees.';
			'serial_codes(''REQ_MIN_SPEED_UNITS_S'') = 72;              % (0x0048) Request the current minimum speed (i.e. motor start speed), in mm/s or deg/s.';
			'serial_codes(''MIN_SPEED_UNITS_S'') = 73;                  % (0x0049) Set/report the current minimum speed (i.e. motor start speed), in mm/s or deg/s.';
			'serial_codes(''ROTARY_MOVEMENT_START'') = 74;              % (0x004A) Indicate that a rotary movement has started.';
			'serial_codes(''ROTARY_MOVEMENT_COMPLETE'') = 75;           % (0x004B) Indicate that a rotary movement is complete.';
			'';
			'serial_codes(''REQ_TRQ_STALL_IGNORE'') = 78;               % (0x004E) Request the current number of steps to ignore before monitoring for stalls.';
			'serial_codes(''TRQ_STALL_IGNORE'') = 79;                   % (0x004F) Set/report the current number of steps to ignore before monitoring for stalls.';
			'serial_codes(''REQ_MAX_SPEED_UNITS_S'') = 80;              % (0x0050) Request the current maximum speed, in mm/s or deg/s.';
			'serial_codes(''MAX_SPEED_UNITS_S'') = 81;                  % (0x0051) Set/report the current maximum speed, in mm/s or deg/s.';
			'serial_codes(''REQ_ACCEL_UNITS_S2'') = 82;                 % (0x0052) Request the current movement acceleration, in mm/s^2 or deg/s^2^2.';
			'serial_codes(''ACCEL_UNITS_S2'') = 83;                     % (0x0053) Set/report the current movement acceleration, in mm/s^2 or deg/s^2^2.';
			'serial_codes(''REQ_MOTOR_CURRENT'') = 84;                  % (0x0054) Request the current motor current setting, in milliamps.';
			'serial_codes(''MOTOR_CURRENT'') = 85;                      % (0x0055) Set/report the current motor current setting, in milliamps.';
			'serial_codes(''REQ_MAX_MOTOR_CURRENT'') = 86;              % (0x0056) Request the maximum possible motor current, in milliamps.';
			'serial_codes(''MAX_MOTOR_CURRENT'') = 87;                  % (0x0057) Set/report the maximum possible motor current, in milliamps.';
			'serial_codes(''REQ_FW_STALL_DETECTION'') = 88;             % (0x0058) Request the firmware-based stall detection setting, on or off.';
			'serial_codes(''FW_STALL_DETECTION'') = 89;                 % (0x0059) Set/report the firmware-based stall detection setting, on or off.';
			'serial_codes(''REQ_HW_STALL_DETECTION'') = 90;             % (0x005A) Request the hardware-based stall detection setting, on or off.';
			'serial_codes(''HW_STALL_DETECTION'') = 91;                 % (0x005B) Set/report the hardware-based stall detection setting, on or off.';
			'serial_codes(''REQ_STALL_THRESH'') = 92;                   % (0x005C) Request the current stall threshold, 0-4095.';
			'serial_codes(''STALL_THRESH'') = 93;                       % (0x005D) Set/report the current stall threshold, 0-4095.';
			'serial_codes(''REQ_TRQ_SCALING'') = 94;                    % (0x005E) Request the torque count scaling setting, 1x or 8x.';
			'serial_codes(''TRQ_SCALING'') = 95;                        % (0x005F) Set/report the torque count scaling setting, 1x or 8x.';
			'serial_codes(''REQ_TRQ_COUNT'') = 96;                      % (0x0060) Request the current torque count, 0-4095.';
			'serial_codes(''TRQ_COUNT'') = 97;                          % (0x0061) Set/report the current torque count, 0-4095.';
			'serial_codes(''MOTOR_STALL'') = 98;                        % (0x0062) Report a motor stall.';
			'serial_codes(''MOTOR_FAULT'') = 99;                        % (0x0063) Report a motor fault, other than a stall (i.e. undervoltage, overcurrent, overtemperature).';
			'';
			'serial_codes(''STREAM_PERIOD'') = 101;                     % (0x0065) Set/report the current streaming period, in milliseconds.';
			'serial_codes(''REQ_STREAM_PERIOD'') = 102;                 % (0x0066) Request the current streaming period, in milliseconds.';
			'serial_codes(''STREAM_ENABLE'') = 103;                     % (0x0067) Enable/disable streaming from the device.';
			'';
			'serial_codes(''AP_DIST_X'') = 110;                         % (0x006E) Set/report the autopositioner x position, in millimeters.';
			'serial_codes(''REQ_AP_DIST_X'') = 111;                     % (0x006F) Request the current autopositioner x position, in millimeters.';
			'';
			'serial_codes(''READ_FROM_NVM'') = 120;                     % (0x0078) Read bytes from non-volatile memory.';
			'serial_codes(''WRITE_TO_NVM'') = 121;                      % (0x0079) Write bytes to non-volatile memory.';
			'serial_codes(''REQ_NVM_SIZE'') = 122;                      % (0x007A) Request the non-volatile memory size.';
			'serial_codes(''NVM_SIZE'') = 123;                          % (0x007B) Report the non-volatile memory size.';
			'';
			'serial_codes(''DISPENSER_READY'') = 144;                   % (0x0090) Report that a dispenser has prepared a reward (i.e. a pellet) for dispensing.';
			'serial_codes(''DISPENSER_RELOAD'') = 145;                  % (0x0091) Command the current dispenser to prepare a reward for dispensing (i.e. reload a pellet).';
			'serial_codes(''DISPENSER_EMPTY'') = 146;                   % (0x0092) Report that a dispenser is empty or cannot detect an available reward.';
			'serial_codes(''PELLET_DETECT_ENABLE'') = 147;              % (0x0093) Enable/disable pellet detection.';
			'serial_codes(''REQ_MAX_RELOAD_ATTEMPTS'') = 148;           % (0x0094) Request the current maximum number of reload attempts.';
			'serial_codes(''MAX_RELOAD_ATTEMPTS'') = 149;               % (0x0095) Set/report the current maximum number of reload attempts.';
			'';
			'serial_codes(''PLAY_TONE'') = 256;                         % (0x0100) Play the specified tone.';
			'serial_codes(''STOP_TONE'') = 257;                         % (0x0101) Stop any currently playing tone.';
			'serial_codes(''REQ_NUM_TONES'') = 258;                     % (0x0102) Request the number of queueable tones.';
			'serial_codes(''NUM_TONES'') = 259;                         % (0x0103) Report the number of queueable tones.';
			'serial_codes(''TONE_INDEX'') = 260;                        % (0x0104) Set/report the current tone index.';
			'serial_codes(''REQ_TONE_INDEX'') = 261;                    % (0x0105) Request the current tone index.';
			'serial_codes(''TONE_FREQ'') = 262;                         % (0x0106) Set/report the frequency of the current tone, in Hertz.';
			'serial_codes(''REQ_TONE_FREQ'') = 263;                     % (0x0107) Request the frequency of the current tone, in Hertz.';
			'serial_codes(''TONE_DUR'') = 264;                          % (0x0108) Set/report the duration of the current tone, in milliseconds.';
			'serial_codes(''REQ_TONE_DUR'') = 265;                      % (0x0109) Return the duration of the current tone in milliseconds.';
			'serial_codes(''TONE_VOLUME'') = 266;                       % (0x010A) Set/report the volume of the current tone, normalized from 0 to 1.';
			'serial_codes(''REQ_TONE_VOLUME'') = 267;                   % (0x010B) Request the volume of the current tone, normalized from 0 to 1.';
			'';
			'serial_codes(''INDICATOR_LEDS_ON'') = 352;                 % (0x0160) Set/report whether the indicator LEDs are turned on (0 = off, 1 = on).';
			'';
			'serial_codes(''CUE_LIGHT_ON'') = 384;                      % (0x0180) Turn on the specified cue light.';
			'serial_codes(''CUE_LIGHT_OFF'') = 385;                     % (0x0181) Turn off any currently-showing cue light.';
			'serial_codes(''NUM_CUE_LIGHTS'') = 386;                    % (0x0182) Report the number of queueable cue lights.';
			'serial_codes(''REQ_NUM_CUE_LIGHTS'') = 387;                % (0x0183) Request the number of queueable cue lights.';
			'serial_codes(''CUE_LIGHT_INDEX'') = 388;                   % (0x0184) Set/report the current cue light index.';
			'serial_codes(''REQ_CUE_LIGHT_INDEX'') = 389;               % (0x0185) Request the current cue light index.';
			'serial_codes(''CUE_LIGHT_RGBW'') = 390;                    % (0x0186) Set/report the RGBW values for the current cue light (0-255).';
			'serial_codes(''REQ_CUE_LIGHT_RGBW'') = 391;                % (0x0187) Request the RGBW values for the current cue light (0-255).';
			'serial_codes(''CUE_LIGHT_DUR'') = 392;                     % (0x0188) Set/report the current cue light duration, in milliseconds.';
			'serial_codes(''REQ_CUE_LIGHT_DUR'') = 393;                 % (0x0189) Request the current cue light duration, in milliseconds.';
			'serial_codes(''CUE_LIGHT_MASK'') = 394;                    % (0x018A) Set/report the cue light enable bitmask.';
			'serial_codes(''REQ_CUE_LIGHT_MASK'') = 395;                % (0x018B) Request the cue light enable bitmask.';
			'serial_codes(''CUE_LIGHT_QUEUE_SIZE'') = 396;              % (0x018C) Set/report the number of queueable cue light stimuli.';
			'serial_codes(''REQ_CUE_LIGHT_QUEUE_SIZE'') = 397;          % (0x018D) Request the number of queueable cue light stimuli.';
			'serial_codes(''CUE_LIGHT_QUEUE_INDEX'') = 398;             % (0x018E) Set/report the current cue light queue index.';
			'serial_codes(''REQ_CUE_LIGHT_QUEUE_INDEX'') = 399;         % (0x018F) Request the current cue light queue index.';
			'';
			'serial_codes(''CAGE_LIGHT_ON'') = 416;                     % (0x01A0) Turn on the overhead cage light.';
			'serial_codes(''CAGE_LIGHT_OFF'') = 417;                    % (0x01A1) Turn off the overhead cage light.';
			'serial_codes(''CAGE_LIGHT_RGBW'') = 418;                   % (0x01A2) Set/report the RGBW values for the overhead cage light (0-255).';
			'serial_codes(''REQ_CAGE_LIGHT_RGBW'') = 419;               % (0x01A3) Request the RGBW values for the overhead cage light (0-255).';
			'serial_codes(''CAGE_LIGHT_DUR'') = 420;                    % (0x01A4) Set/report the overhead cage light duration, in milliseconds.';
			'serial_codes(''REQ_CAGE_LIGHT_DUR'') = 421;                % (0x01A5) Request the overhead cage light duration, in milliseconds.';
			'';
			'serial_codes(''POKE_BITMASK'') = 512;                      % (0x0200) Set/report the current nosepoke status bitmask.';
			'serial_codes(''REQ_POKE_BITMASK'') = 513;                  % (0x0201) Request the current nosepoke status bitmask.';
			'serial_codes(''POKE_ADC'') = 514;                          % (0x0202) Report the current nosepoke analog reading (returns both the filtered and raw value).';
			'serial_codes(''REQ_POKE_ADC'') = 515;                      % (0x0203) Request the current nosepoke analog reading.';
			'serial_codes(''POKE_MINMAX'') = 516;                       % (0x0204) Set/report the minimum and maximum ADC values of the nosepoke infrared sensor history, in ADC ticks.';
			'serial_codes(''REQ_POKE_MINMAX'') = 517;                   % (0x0205) Request the minimum and maximum ADC values of the nosepoke infrared sensor history, in ADC ticks.';
			'serial_codes(''POKE_THRESH_FL'') = 518;                    % (0x0206) Set/report the current nosepoke threshold setting, normalized from 0 to 1.';
			'serial_codes(''REQ_POKE_THRESH_FL'') = 519;                % (0x0207) Request the current nosepoke threshold setting, normalized from 0 to 1.';
			'serial_codes(''POKE_THRESH_ADC'') = 520;                   % (0x0208) Set/report the current nosepoke threshold setting, in ADC ticks.';
			'serial_codes(''REQ_POKE_THRESH_ADC'') = 521;               % (0x0209) Request the current nosepoke auto-threshold setting, in ADC ticks.';
			'serial_codes(''POKE_THRESH_AUTO'') = 522;                  % (0x020A) Set/report the current nosepoke auto-thresholding setting (0 = fixed, 1 = autoset).';
			'serial_codes(''REQ_POKE_THRESH_AUTO'') = 523;              % (0x020B) Request the current nosepoke auto-thresholding setting (0 = fixed, 1 = autoset).';
			'serial_codes(''POKE_RESET'') = 524;                        % (0x020C) Reset the nosepoke infrared sensor history.';
			'serial_codes(''POKE_INDEX'') = 525;                        % (0x020D) Set/report the current nosepoke index for multi-nosepoke modules.';
			'serial_codes(''REQ_POKE_INDEX'') = 526;                    % (0x020E) Request the current nosepoke index for multi-nosepoke modules.';
			'serial_codes(''POKE_MIN_RANGE'') = 527;                    % (0x020F) Set/report the minimum signal range for positive detection with the current nosepoke, in ADC ticks.';
			'serial_codes(''REQ_POKE_MIN_RANGE'') = 528;                % (0x0210) Request the minimum signal range for positive detection with the current nosepoke, in ADC ticks.';
			'serial_codes(''POKE_LOWPASS_CUTOFF'') = 529;               % (0x0211) Set/report the current nosepoke sensor low-pass filter cutoff frequency, in Hz.';
			'serial_codes(''REQ_POKE_LOWPASS_CUTOFF'') = 530;           % (0x0212) Request the current nosepoke sensor low-pass filter cutoff frequency, in Hz.';
			'';
			'serial_codes(''CAPSENSE_BITMASK'') = 624;                  % (0x0270) Set/report the current capacitive sensor status bitmask.';
			'serial_codes(''REQ_CAPSENSE_BITMASK'') = 625;              % (0x0271) Request the current capacitive sensor status bitmask.';
			'serial_codes(''CAPSENSE_INDEX'') = 626;                    % (0x0272) Set/report the current capacitive sensor index.';
			'serial_codes(''REQ_CAPSENSE_INDEX'') = 627;                % (0x0273) Request the current capacitive sensor index.';
			'serial_codes(''CAPSENSE_SENSITIVITY'') = 628;              % (0x0274) Set/report the current capacitive sensor sensitivity setting, normalized from 0 to 1.';
			'serial_codes(''REQ_CAPSENSE_SENSITIVITY'') = 629;          % (0x0275) Request the current capacitive sensor sensitivity setting, normalized from 0 to 1.';
			'serial_codes(''CAPSENSE_RESET'') = 630;                    % (0x0276) Reset the current capacitance sensor history.';
			'';
			'serial_codes(''CAPSENSE_VALUE'') = 640;                    % (0x0280) Report the current capacitance sensor reading, in ADC ticks or clock cycles.';
			'serial_codes(''REQ_CAPSENSE_VALUE'') = 641;                % (0x0281) Request the current capacitance sensor reading, in ADC ticks or clock cycles.';
			'serial_codes(''CAPSENSE_MINMAX'') = 642;                   % (0x0282) Report the minimum and maximum values of the current capacitive sensor''s history.';
			'serial_codes(''REQ_CAPSENSE_MINMAX'') = 643;               % (0x0283) Request the minimum and maximum values of the current capacitive sensor''s history.';
			'serial_codes(''CAPSENSE_MIN_RANGE'') = 644;                % (0x0284) Set/report the minimum signal range for positive detection with the current capacitive sensor.';
			'serial_codes(''REQ_CAPSENSE_MIN_RANGE'') = 645;            % (0x0285) Request the minimum signal range for positive detection with the current capacitive sensor.';
			'serial_codes(''CAPSENSE_THRESH_FIXED'') = 646;             % (0x0286) Set/report a fixed threshold for the current capacitive sensor, in ADC ticks or clock cycles.';
			'serial_codes(''REQ_CAPSENSE_THRESH_FIXED'') = 647;         % (0x0287) Request the current threshold for the current capacitive sensor, in ADC ticks or clock cycles.';
			'serial_codes(''CAPSENSE_THRESH_AUTO'') = 648;              % (0x0288) Set/report the current capacitive sensor auto-thresholding setting (0 = fixed, 1 = autoset <default>).';
			'serial_codes(''REQ_CAPSENSE_THRESH_AUTO'') = 649;          % (0x0289) Request the current capacitive sensor auto-thresholding setting (0 = fixed, 1 = autoset <default>).';
			'serial_codes(''CAPSENSE_RESET_TIMEOUT'') = 650;            % (0x028A) Set/report the current capacitive sensor reset timeout duration, in milliseconds (0 = no time-out reset).';
			'serial_codes(''REQ_CAPSENSE_RESET_TIMEOUT'') = 651;        % (0x028B) Request the current capacitive sensor reset timeout duration, in milliseconds (0 = no time-out reset).';
			'serial_codes(''CAPSENSE_SAMPLE_SIZE'') = 652;              % (0x028C) Set/report the current capacitive sensor repeated measurement sample size.';
			'serial_codes(''REQ_CAPSENSE_SAMPLE_SIZE'') = 653;          % (0x028D) Request the current capacitive sensor repeated measurement sample size.';
			'serial_codes(''CAPSENSE_BOXSMOOTH_N'') = 654;              % (0x028E) Set/report the current capacitive sensor box-smoothing size (0 = no box-smoothing). *DEPRECATED*';
			'serial_codes(''REQ_CAPSENSE_BOXSMOOTH_N'') = 655;          % (0x028F) Request the current capacitive sensor box-smoothing size (0 = no box-smoothing). *DEPRECATED*';
			'serial_codes(''CAPSENSE_DIFFERENTIATE'') = 656;            % (0x0290) Set/report the current capacitive sensor differentation mode (0 = off/raw signal, 1 = on/differentiated). *DEPRECATED*';
			'serial_codes(''REQ_CAPSENSE_DIFFERENTIATE'') = 657;        % (0x0291) Request the current capacitive sensor differentation mode (0 = off/raw signal, 1 = on/differentiated). *DEPRECATED*';
			'serial_codes(''CAPSENSE_HIGHPASS_CUTOFF'') = 658;          % (0x0292) Set/report the current capacitive sensor high-pass filter cutoff frequency, in Hz.';
			'serial_codes(''REQ_CAPSENSE_HIGHPASS_CUTOFF'') = 659;      % (0x0293) Request the current capacitive sensor high-pass filter cutoff frequency, in Hz.';
			'serial_codes(''CAPSENSE_FILTER_TYPE'') = 660;              % (0x0294) Set/report the current capacitive sensor filter type (0 = none, 1 = low-pass, 2 = high-pass). *DEPRECATED*';
			'serial_codes(''REQ_CAPSENSE_FILTER_TYPE'') = 661;          % (0x0295) Request the current capacitive sensor filter type (0 = none, 1 = low-pass, 2 = high-pass). *DEPRECATED*';
			'serial_codes(''CAPSENSE_LOWPASS_CUTOFF'') = 662;           % (0x0296) Set/report the current capacitive sensor low-pass filter cutoff frequency, in Hz.';
			'serial_codes(''REQ_CAPSENSE_LOWPASS_CUTOFF'') = 663;       % (0x0297) Request the current capacitive sensor low-pass filter cutoff frequency, in Hz.';
			'';
			'serial_codes(''REQ_THERM_PIXELS_INT_K'') = 768;            % (0x0300) Request a thermal pixel image as 16-bit unsigned integers in units of deciKelvin (dK, or Kelvin * 10).';
			'serial_codes(''THERM_PIXELS_INT_K'') = 769;                % (0x0301) Report a thermal image as 16-bit unsigned integers in units of deciKelvin (dK, or Kelvin * 10).';
			'serial_codes(''REQ_THERM_PIXELS_FP62'') = 770;             % (0x0302) Request a thermal pixel image as a fixed-point 6/2 type (6 bits for the unsigned integer part, 2 bits for the decimal part), in units of Celcius.';
			'serial_codes(''THERM_PIXELS_FP62'') = 771;                 % (0x0303) Report a thermal pixel image as a fixed-point 6/2 type (6 bits for the unsigned integer part, 2 bits for the decimal part), in units of Celcius. This allows temperatures from 0 to 63.75 C.';
			'';
			'serial_codes(''REQ_THERM_XY_PIX'') = 784;                  % (0x0310) Request the current thermal hotspot x-y position, in units of pixels.';
			'serial_codes(''THERM_XY_PIX'') = 785;                      % (0x0311) Report the current thermal hotspot x-y position, in units of pixels.';
			'';
			'serial_codes(''REQ_AMBIENT_TEMP'') = 800;                  % (0x0320) Request the current ambient temperature as a 32-bit float, in units of Celsius.';
			'serial_codes(''AMBIENT_TEMP'') = 801;                      % (0x0321) Report the current ambient temperature as a 32-bit float, in units of Celsius.';
			'';
			'serial_codes(''REQ_TOF_DIST'') = 896;                      % (0x0380) Request the current time-of-flight distance reading, in units of millimeters (float32).';
			'serial_codes(''TOF_DIST'') = 897;                          % (0x0381) Report the current time-of-flight distance reading, in units of millimeters (float32).';
			'';
			'serial_codes(''REQ_OPTICAL_FLOW_XY'') = 1024;              % (0x0400) Request the current x- and y-coordinates from the currently-selected optical flow sensor, as 32-bit integers.';
			'serial_codes(''OPTICAL_FLOW_XY'') = 1025;                  % (0x0401) Report the current x- and y-coordinates from the currently-selected optical flow sensor, as 32-bit integers.';
			'serial_codes(''REQ_OPTICAL_FLOW_DELTA_XY'') = 1026;        % (0x0402) Request the current change in x- and y-coordinates from the currently-selected optical flow sensor, as 32-bit integers.';
			'serial_codes(''OPTICAL_FLOW_DELTA_XY'') = 1027;            % (0x0403) Report the current change in x- and y-coordinates from the currently-selected optical flow sensor, as 32-bit integers.';
			'serial_codes(''REQ_OPTICAL_FLOW_DELTA_3VEC'') = 1028;      % (0x0404) Request the current change in value from the three selected optical flow vectors, as 16-bit integers.';
			'serial_codes(''OPTICAL_FLOW_DELTA_3VEC'') = 1029;          % (0x0405) Report the current change in value from the three selected optical flow vectors, as 16-bit integers.';
			'serial_codes(''REQ_OPTICAL_FLOW_INDEX'') = 1030;           % (0x0406) Request the current optical flow sensor index.';
			'serial_codes(''OPTICAL_FLOW_INDEX'') = 1031;               % (0x0407) Set/report the current optical flow sensor index.';
			'serial_codes(''OPTICAL_FLOW_RESET'') = 1032;               % (0x0408) Reset the current x- and y- counts for all optical flow sensors on the module.';
			'';
			'serial_codes(''REQ_TTL_INDEX'') = 1280;                    % (0x0500) Request the current TTL I/O index.';
			'serial_codes(''TTL_INDEX'') = 1281;                        % (0x0501) Set/report the current TTL I/O index.';
			'serial_codes(''TTL_START_PULSE'') = 1282;                  % (0x0502) Immediately start a TTL pulse on the specifed I/O.';
			'serial_codes(''TTL_STOP_PULSE'') = 1283;                   % (0x0503) Immediately stop a TTL pulse on the specifed I/O.';
			'serial_codes(''REQ_TTL_PULSE_DUR'') = 1284;                % (0x0504) Request the current TTL pulse duration, in milliseconds.';
			'serial_codes(''TTL_PULSE_DUR'') = 1285;                    % (0x0505) Set/report the current TTL pulse duration, in milliseconds.';
			'serial_codes(''REQ_TTL_PULSE_VALS'') = 1286;               % (0x0506) Request the current TTL pulse "on" and "off" values.';
			'serial_codes(''TTL_PULSE_OFF_VAL'') = 1287;                % (0x0507) Set/report the current TTL pulse "off" value.';
			'serial_codes(''TTL_PULSE_ON_VAL'') = 1288;                 % (0x0508) Set/report the current TTL pulse "on" value.';
			'serial_codes(''TTL_XINT'') = 1289;                         % (0x0509) Report a TTL input pseudo-interrupt event.';
			'serial_codes(''REQ_TTL_XINT_THRESH'') = 1290;              % (0x050A) Request the current TTL input pseudo-interrupt threshold.';
			'serial_codes(''TTL_XINT_THRESH'') = 1291;                  % (0x050B) Set/report the current TTL input pseudo-interrupt threshold.';
			'serial_codes(''REQ_TTL_XINT_MODE'') = 1292;                % (0x050C) Request the current TTL input pseudo-interrupt mode.';
			'serial_codes(''TTL_XINT_MODE'') = 1293;                    % (0x050D) Set/report the current TTL input pseudo-interrupt mode.';
			'serial_codes(''TTL_SET_DOUT'') = 1294;                     % (0x050E) Set the TTL digital output value.';
			'serial_codes(''REQ_TTL_DIGITAL_BITMASK'') = 1295;          % (0x050F) Request the current TTL digital status bitmask.';
			'serial_codes(''TTL_DIGITAL_BITMASK'') = 1296;              % (0x0510) Report the current TTL digital status bitmask.';
			'serial_codes(''TTL_SET_AOUT'') = 1297;                     % (0x0511) Set the specified TTL I/O''s analog output value.';
			'serial_codes(''REQ_TTL_AIN'') = 1298;                      % (0x0512) Request the specified TTL I/O''s analog input value.';
			'serial_codes(''TTL_AIN'') = 1299;                          % (0x0513) Report the specified TTL I/O''s analog input value.';
			'';
			'serial_codes(''VIB_DUR'') = 16384;                         % (0x4000) Set/report the current vibration pulse duration, in microseconds.';
			'serial_codes(''REQ_VIB_DUR'') = 16385;                     % (0x4001) Request the current vibration pulse duration, in microseconds.';
			'serial_codes(''VIB_IPI'') = 16386;                         % (0x4002) Set/report the current vibration train onset-to-onset inter-pulse interval, in microseconds.';
			'serial_codes(''REQ_VIB_IPI'') = 16387;                     % (0x4003) Request the current vibration train onset-to-onset inter-pulse interval, in microseconds.';
			'serial_codes(''VIB_N_PULSE'') = 16388;                     % (0x4004) Set/report the current vibration train duration, in number of pulses.';
			'serial_codes(''REQ_VIB_N_PULSE'') = 16389;                 % (0x4005) Request the current vibration train duration, in number of pulses.';
			'serial_codes(''VIB_GAP'') = 16390;                         % (0x4006) Set/report the current vibration train skipped pulses starting and stopping index.';
			'serial_codes(''REQ_VIB_GAP'') = 16391;                     % (0x4007) Request the current vibration train skipped pulses starting and stopping index.';
			'';
			'serial_codes(''START_VIB'') = 16394;                       % (0x400A) Immediately start the vibration pulse train.';
			'serial_codes(''STOP_VIB'') = 16395;                        % (0x400B) Immediately stop the vibration pulse train.';
			'serial_codes(''VIB_MASK_ENABLE'') = 16396;                 % (0x400C) Enable/disable vibration tone masking (0 = disabled, 1 = enabled).';
			'serial_codes(''VIB_MASK_TONE_INDEX'') = 16397;             % (0x400D) Set/report the current tone repertoire index for the masking tone.';
			'serial_codes(''REQ_VIB_MASK_TONE_INDEX'') = 16398;         % (0x400E) Request the current tone repertoire index for the masking tone.';
			'serial_codes(''VIB_TASK_MODE'') = 16399;                   % (0x400F) Set/report the current vibration task mode (1 = BURST, 2 = GAP).';
			'serial_codes(''REQ_VIB_TASK_MODE'') = 16400;               % (0x4010) Request the current vibration task mode (1 = BURST, 2 = GAP).';
			'serial_codes(''VIB_INDEX'') = 16401;                       % (0x4011) Set/report the current vibration motor/actuator index.';
			'serial_codes(''REQ_VIB_INDEX'') = 16402;                   % (0x4012) Request the current vibration motor/actuator index.';
			'';
			'serial_codes(''STAP_STEPS_PER_ROT'') = 16665;              % (0x4119) Set/report the number of steps per full revolution for the stepper motor.';
			'serial_codes(''STAP_REQ_STEPS_PER_ROT'') = 16666;          % (0x411A) Return the current number of steps per full revolution for the stepper motor.';
			'';
			'serial_codes(''STAP_MICROSTEP'') = 16670;                  % (0x411E) Set/report the microstepping multiplier.';
			'serial_codes(''STAP_REQ_MICROSTEP'') = 16671;              % (0x411F) Request the current microstepping multiplier.';
			'serial_codes(''CUR_POS'') = 16672;                         % (0x4120) Set/report the target/current handle position, in micrometers.';
			'serial_codes(''REQ_CUR_POS'') = 16673;                     % (0x4121) Request the current handle position, in micrometers.';
			'serial_codes(''MIN_SPEED'') = 16674;                       % (0x4122) Set/report the minimum movement speed, in micrometers/second.';
			'serial_codes(''REQ_MIN_SPEED'') = 16675;                   % (0x4123) Request the minimum movement speed, in micrometers/second.';
			'serial_codes(''MAX_SPEED'') = 16676;                       % (0x4124) Set/report the maximum movement speed, in micrometers/second.';
			'serial_codes(''REQ_MAX_SPEED'') = 16677;                   % (0x4125) Request the maximum movement speed, in micrometers/second.';
			'serial_codes(''RAMP_N'') = 16678;                          % (0x4126) Set/report the cosine ramp length, in steps.';
			'serial_codes(''REQ_RAMP_N'') = 16679;                      % (0x4127) Request the cosine ramp length, in steps.';
			'serial_codes(''PITCH_CIRC'') = 16680;                      % (0x4128) Set/report the driving gear pitch circumference, in micrometers.';
			'serial_codes(''REQ_PITCH_CIRC'') = 16681;                  % (0x4129) Request the driving gear pitch circumference, in micrometers.';
			'serial_codes(''CENTER_OFFSET'') = 16682;                   % (0x412A) Set/report the center-to-slot detector offset, in micrometers.';
			'serial_codes(''REQ_CENTER_OFFSET'') = 16683;               % (0x412B) Request the center-to-slot detector offset, in micrometers.';
			'';
			'serial_codes(''TRIAL_SPEED'') = 16688;                     % (0x4130) Set/report the trial movement speed, in micrometers/second.';
			'serial_codes(''REQ_TRIAL_SPEED'') = 16689;                 % (0x4131) Request the trial movement speed, in micrometers/second.';
			'serial_codes(''RECENTER'') = 16690;                        % (0x4132) Rapidly re-center the handle to the home position state.';
			'serial_codes(''RECENTER_COMPLETE'') = 16691;               % (0x4133) Indicate that the handle is recentered.';
			'';
			'serial_codes(''SINGLE_EXCURSION'') = 16705;                % (0x4141) Select excursion type:  direct single motion (L/R)';
			'serial_codes(''INCREASING_EXCURSION'') = 16706;            % (0x4142) Select excursion type:  deviation increase from midline';
			'serial_codes(''DRIFTING_EXCURSION'') = 16707;              % (0x4143) Select excursion type:  R/L motion with a net direction';
			'serial_codes(''SELECT_TEST_DEV_DEG'') = 16708;             % (0x4144) Set deviation degrees:  used in mode 65, 66 and 67';
			'serial_codes(''SELECT_BASE_DEV_DEG'') = 16709;             % (0x4145) Set the baseline rocking: used in mode 66 and 67';
			'serial_codes(''SELECT_SYMMETRY'') = 16710;                 % (0x4146) Sets oscillation around midline or from mindline';
			'serial_codes(''SELECT_ACCEL'') = 16711;                    % (0x4147) ';
			'serial_codes(''SET_EXCURSION_TYPE'') = 16712;              % (0x4148) Set the excursion type (49 = simple movement, 50 = wandering wobble)';
			'serial_codes(''GET_EXCURSION_TYPE'') = 16713;              % (0x4149) Get the current excurion type.';
			'';
			'serial_codes(''CUR_DEBUG_MODE'') = 25924;                  % (0x6544) Report the current debug mode ("Debug_ON_" or "Debug_OFF");';
			'';
			'serial_codes(''TOGGLE_DEBUG_MODE'') = 25956;               % (0x6564) Toggle OTSC debugging mode (type "db" in a serial monitor).';
			'';
			'serial_codes(''REQ_BAUDRATE_TEST'') = 29794;               % (0x7462) Request a baud rate test packet (uint8 values 0-255, in order). Type ''bt'' into the serial monitor to run.';
			'serial_codes(''BAUDRATE_TEST'') = 29795;                   % (0x7463) Send/receive a baud rate test packet (uint8 values 0-x, in order).';
			'serial_codes(''BAUDRATE_TEST_RESULTS'') = 29796;           % (0x7464) Report baud rate test results (correct count, byte count).';
			'serial_codes(''REPORT_BAUDRATE'') = 29797;                 % (0x7465) Report the current baud rate (in Hz).';
			'';
			'serial_codes(''REQ_LOADCELL_VAL_ADC'') = 43526;            % (0xAA06) Request the current force/loadcell value, in ADC ticks (uint16).';
			'serial_codes(''LOADCELL_VAL_ADC'') = 43527;                % (0xAA07) Report the current force/loadcell value, in ADC ticks (uint16).';
			'serial_codes(''LOADCELL_INDEX'') = 43528;                  % (0xAA08) Set/report the current loadcell/force sensor index.';
			'serial_codes(''REQ_LOADCELL_INDEX'') = 43529;              % (0xAA09) Request the current loadcell/force  sensor index.';
			'serial_codes(''REQ_LOADCELL_VAL_GM'') = 43530;             % (0xAA0A) Request the current force/loadcell value, in units of grams (float).';
			'serial_codes(''LOADCELL_VAL_GM'') = 43531;                 % (0xAA0B) Report the current force/loadcell value, in units of grams (float).';
			'serial_codes(''REQ_LOADCELL_CAL_BASELINE'') = 43532;       % (0xAA0C) Request the current loadcell/force calibration baseline, in ADC ticks (float).';
			'serial_codes(''LOADCELL_CAL_BASELINE'') = 43533;           % (0xAA0D) Set/report the current loadcell/force calibration baseline, in ADC ticks (float).';
			'serial_codes(''REQ_LOADCELL_CAL_SLOPE'') = 43534;          % (0xAA0E) Request the current loadcell/force calibration slope, in grams per ADC tick (float).';
			'serial_codes(''LOADCELL_CAL_SLOPE'') = 43535;              % (0xAA0F) Set/report the current loadcell/force calibration slope, in grams per ADC tick (float).';
			'serial_codes(''REQ_LOADCELL_DIGPOT_BASELINE'') = 43536;    % (0xAA10) Request the current loadcell/force baseline-adjusting digital potentiometer setting, scaled 0-1 (float).';
			'serial_codes(''LOADCELL_DIGPOT_BASELINE'') = 43537;        % (0xAA11) Set/report the current loadcell/force baseline-adjusting digital potentiometer setting, scaled 0-1 (float).';
			'serial_codes(''REQ_LOADCELL_VAL_DGM'') = 43538;            % (0xAA12) Request the current force/loadcell value, in units of decigrams (int16).';
			'serial_codes(''LOADCELL_VAL_DGM'') = 43539;                % (0xAA13) Report the current force/loadcell value, in units of decigrams (int16).';
			'serial_codes(''REQ_LOADCELL_GAIN'') = 43540;               % (0xAA14) Request the current force/loadcell gain setting (float).';
			'serial_codes(''LOADCELL_GAIN'') = 43541;                   % (0xAA15) Set/report the current force/loadcell gain setting (float).';
			'serial_codes(''LOADCELL_BASELINE_MEASURE'') = 43542;       % (0xAA16) Measure the current loadcell/force sensor baseline (loadcell should be unloaded).';
			'serial_codes(''LOADCELL_BASELINE_ADJUST'') = 43543;        % (0xAA17) Adjust the current loadcell/force baseline-adjusting digital potentiometer to be as close as possible to the specified ADC target (loadcell should be unloaded).';
			'serial_codes(''LOADCELL_CAL_SLOPE_MEASURE'') = 43544;      % (0xAA18) Measure the current loadcell/force sensor calibration slope given the specified force/weight.';
			'serial_codes(''STEPS_PER_ROT'') = 43545;                   % (0xAA19) Set/report the number of steps per full revolution for the stepper motor.';
			'serial_codes(''REQ_STEPS_PER_ROT'') = 43546;               % (0xAA1A) Return the current number of steps per full revolution for the stepper motor.';
			'';
			'serial_codes(''MICROSTEP'') = 43550;                       % (0xAA1E) Set/report the microstepping multiplier.';
			'serial_codes(''REQ_MICROSTEP'') = 43551;                   % (0xAA1F) Request the current microstepping multiplier.';
			'';
			'serial_codes(''NUM_PADS'') = 43560;                        % (0xAA28) Set/report the number of texture positions on the carousel disc.';
			'serial_codes(''REQ_NUM_PADS'') = 43561;                    % (0xAA29) Request the number of texture positions on the carousel disc.';
			'';
			'serial_codes(''CUR_PAD_I'') = 43570;                       % (0xAA32) Set/report the current texture position index.';
			'serial_codes(''REQ_CUR_PAD_I'') = 43571;                   % (0xAA33) Return the current texture position index.';
			'serial_codes(''PAD_LABEL'') = 43572;                       % (0xAA34) Set/report the current position label.';
			'serial_codes(''REQ_PAD_LABEL'') = 43573;                   % (0xAA35) Return the current position label.';
			'serial_codes(''ROTATE_CW'') = 43574;                       % (0xAA36) Rotate one position clockwise (viewed from above).';
			'serial_codes(''ROTATE_CCW'') = 43575;                      % (0xAA37) Rotate one position counter-clockwise (viewed from above).';
			'';
			'serial_codes(''VOLTAGE_IN'') = 43776;                      % (0xAB00) Report the current input voltage to the device.';
			'serial_codes(''REQ_VOLTAGE_IN'') = 43777;                  % (0xAB01) Request the current input voltage to the device.';
			'serial_codes(''CURRENT_IN'') = 43778;                      % (0xAB02) Report the current input current to the device, in milliamps.';
			'serial_codes(''REQ_CURRENT_IN'') = 43779;                  % (0xAB03) Request the current input current to the device, in milliamps.';
			'';
			'serial_codes(''COMM_VERIFY'') = 43981;                     % (0xABCD) Verify use of the OTSC serial code library, responding to a REQ_COMM_VERIFY block.';
			'';
			'serial_codes(''PASSTHRU_DOWN'') = 48350;                   % (0xBCDE) Route the immediately following block downstream to the specified port or VPB device.';
			'serial_codes(''PASSTHRU_UP'') = 48351;                     % (0xBCDF) Route the immediately following block upstream, typically to the controller or computer.';
			'serial_codes(''PASSTHRU_HOLD'') = 48352;                   % (0xBCE0) Route all following blocks to the specified port or VPB device until the serial line is inactive for a set duration.';
			'serial_codes(''PASSTHRU_HOLD_DUR'') = 48353;               % (0xBCE1) Set/report the timeout duration for a passthrough hold, in milliseconds.';
			'serial_codes(''REQ_PASSTHRU_HOLD_DUR'') = 48354;           % (0xBCE2) Request the timeout duration for a passthrough hold, in milliseconds.';
			'';
			'serial_codes(''REQ_OTMP_IOUT'') = 48368;                   % (0xBCF0) Request the OmniTrak Module Port (OTMP) output current for the specified port, in milliamps.';
			'serial_codes(''OTMP_IOUT'') = 48369;                       % (0xBCF1) Report the OmniTrak Module Port (OTMP) output current for the specified port, in milliamps.';
			'serial_codes(''REQ_OTMP_ACTIVE_PORTS'') = 48370;           % (0xBCF2) Request a bitmask indicating which OmniTrak Module Ports (OTMPs) are active based on current draw.';
			'serial_codes(''OTMP_ACTIVE_PORTS'') = 48371;               % (0xBCF3) Report a bitmask indicating which OmniTrak Module Ports (OTMPs) are active based on current draw.';
			'serial_codes(''REQ_OTMP_HIGH_VOLT'') = 48372;              % (0xBCF4) Request the current high voltage supply setting for the specified OmniTrak Module Port (0 = off <default>, 1 = high voltage enabled).';
			'serial_codes(''OTMP_HIGH_VOLT'') = 48373;                  % (0xBCF5) Set/report the current high voltage supply setting for the specified OmniTrak Module Port (0 = off <default>, 1 = high voltage enabled).';
			'serial_codes(''REQ_OTMP_OVERCURRENT_PORTS'') = 48374;      % (0xBCF6) Request a bitmask indicating which OmniTrak Module Ports (OTMPs) are in overcurrent shutdown.';
			'serial_codes(''OTMP_OVERCURRENT_PORTS'') = 48375;          % (0xBCF7) Report a bitmask indicating which OmniTrak Module Ports (OTMPs) are in overcurrent shutdown.';
			'serial_codes(''OTMP_ALERT_RESET'') = 48376;                % (0xBCF8) Send a reset pulse to the specified OmniTrak module port''s latched overcurrent comparator.';
			'serial_codes(''REQ_OTMP_CHUNK_SIZE'') = 48377;             % (0xBCF9) Request the current serial "chunk" size required for transmission from the specified OmniTrak Module Port (OTMP), in bytes.';
			'serial_codes(''OTMP_CHUNK_SIZE'') = 48378;                 % (0xBCFA) Set/report the current serial "chunk" size required for transmission from the specified OmniTrak Module Port (OTMP), in bytes.';
			'serial_codes(''REQ_OTMP_PASSTHRU_TIMEOUT'') = 48379;       % (0xBCFB) Request the current serial "chunk" timeout for the specified OmniTrak Module Port (OTMP), in microseconds.';
			'serial_codes(''OTMP_PASSTHRU_TIMEOUT'') = 48380;           % (0xBCFC) Set/report the current serial "chunk" timeout for the specified OmniTrak Module Port (OTMP), in microseconds.';
			'serial_codes(''OTMP_RESET_CHUNKING'') = 48381;             % (0xBCFD) Reset the serial "chunk" size and "chunk" timeout to the defaults for all OmniTrak Module Ports (OTMPs).';
			'';
			'serial_codes(''BROADCAST_OTMP'') = 48586;                  % (0xBDCA) Route the immediately following block to all available OmniTrak Module Ports (RJ45 jacks).';
			'';
			'serial_codes(''BLE_CONNECT'') = 49153;                     % (0xC001) Connect to a Bluetooth Low Energy (BLE) device that is advertising with a particular (local) name, address, or (service) UUID.';
			'serial_codes(''BLE_DISCONNECT'') = 49154;                  % (0xC002) Disconnect from the currently connected Bluetooth Low Energy (BLE) device.';
			'serial_codes(''BLE_CONNECTED'') = 49155;                   % (0xC003) Indicate that a Bluetooth Low Energy (BLE) device connection is active (0 = closed/inactive, 1 = active).';
			'serial_codes(''REQ_BLE_CONNECTED'') = 49156;               % (0xC004) Request the Bluetooth Low Energy (BLE) device connection status.';
			'serial_codes(''BLE_CHARACTERISTIC_WRITE'') = 49157;        % (0xC005) Write the specified bytes to the specified characteristic on the Bluetooth Low Energy (BLE) device.';
			'serial_codes(''BLE_CHAR_NOTIFY'') = 49158;                 % (0xC006) Report a Bluetooth Low Energy (BLE) device characteristic notification value.';
			'serial_codes(''BLE_SCAN'') = 49159;                        % (0xC007) Scan for all available BLE devices and return the addresses, local names, and service UUIDs of each one found.';
			'serial_codes(''BLE_DEVICE_NAME'') = 49160;                 % (0xC008) Report the address, local name, and service UUID of an available BLE device.';
			'serial_codes(''BLE_DEVICE_LIST_SERVICES'') = 49161;        % (0xC009) Request the list of available services from the connected BLE device.';
		};

	case 'Vulintus_Load_OTSC_Packet_Info'
		txt =	{
			'function packet_info = Vulintus_Load_OTSC_Packet_Info';
			'';
			'%	Vulintus_Load_OTSC_Packet_Info.m';
			'%';
			'%	copyright, Vulintus, Inc.';
			'%';
			'%	OmniTrak Serial Communication (OTSC) packet information.';
			'%';
			'%	Library documentation:';
			'%	https://github.com/Vulintus/OmniTrak_Serial_Communication';
			'%';
			'%	This function was programmatically generated: 2025-06-09, 07:46:01 (UTC)';
			'%';
			'';
			'packet_info = dictionary;';
			'';
			'';
			'% DEVICE_ID (0x0003): Set/report the device type ID number.';
			'packet_info(3) = struct(		''name'',			''DEVICE_ID'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% USERSET_ALIAS (0x0005): Set/report the user-set name for the device.';
			'packet_info(5) = struct(		''name'',			''USERSET_ALIAS'',...';
			'								''payload'',		{{NaN, ''char''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% VULINTUS_ALIAS (0x0007): Set/report the Vulintus alias (adjective/noun serial number) for the device.';
			'packet_info(7) = struct(		''name'',			''VULINTUS_ALIAS'',...';
			'								''payload'',		{{NaN, ''char''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% BOARD_VER (0x0009): Report the circuit board version number.';
			'packet_info(9) = struct(		''name'',			''BOARD_VER'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MCU_SERIALNUM (0x000D): Report the device microcontroller serial number.';
			'packet_info(13) = struct(		''name'',			''MCU_SERIALNUM'',...';
			'								''payload'',		{{NaN, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% MAX_BAUDRATE (0x000F): Report the maximum serial baud rate for supported by the device, in Hz.';
			'packet_info(15) = struct(		''name'',			''MAX_BAUDRATE'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% PROGRAM_MODE (0x0012): Set/report the current firmware program mode.';
			'packet_info(18) = struct(		''name'',			''PROGRAM_MODE'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MILLIS_MICROS (0x0014): Report the microcontroller''s current millisecond and microsecond clock readings.';
			'packet_info(20) = struct(		''name'',			''MILLIS_MICROS'',...';
			'								''payload'',		{{2, ''uint32''}},...';
			'								''min_bytes'',	10,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% FW_FILENAME (0x0015): Report the firmware filename.';
			'packet_info(21) = struct(		''name'',			''FW_FILENAME'',...';
			'								''payload'',		{{NaN, ''char''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% FW_DATE (0x0017): Report the firmware upload date.';
			'packet_info(23) = struct(		''name'',			''FW_DATE'',...';
			'								''payload'',		{{NaN, ''char''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% FW_TIME (0x0019): Report the firmware upload time.';
			'packet_info(25) = struct(		''name'',			''FW_TIME'',...';
			'								''payload'',		{{NaN, ''char''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% UNKNOWN_BLOCK_ERROR (0x0021): Indicate an unknown block code error.';
			'packet_info(33) = struct(		''name'',			''UNKNOWN_BLOCK_ERROR'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% ERROR_INDICATOR (0x0022): Indicate an error and send the associated error code.';
			'packet_info(34) = struct(		''name'',			''ERROR_INDICATOR'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% REBOOTING (0x0023): Indicate that the device is rebooting.';
			'packet_info(35) = struct(		''name'',			''REBOOTING'',...';
			'								''payload'',		{{}},...';
			'								''min_bytes'',	2,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CUR_FEEDER (0x0033): Set/report the current dispenser index.';
			'packet_info(51) = struct(		''name'',			''CUR_FEEDER'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% DISPENSE_FIRMWARE (0x0038): Report that a feeding was automatically triggered in the device firmware.';
			'packet_info(56) = struct(		''name'',			''DISPENSE_FIRMWARE'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% HOMING_COMPLETE (0x003C): Indicate that a module''s homing routine is complete.';
			'packet_info(60) = struct(		''name'',			''HOMING_COMPLETE'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MOVEMENT_START (0x003D): Indicate that a linear/rotary movement has started.';
			'packet_info(61) = struct(		''name'',			''MOVEMENT_START'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	11,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CUR_POS_UNITS (0x0043): Set/report the current position of the module movement, in millimeters or degrees.';
			'packet_info(67) = struct(		''name'',			''CUR_POS_UNITS'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MIN_POS_UNITS (0x0045): Set/report the current minimum position of a module movement, in millimeters or degrees.';
			'packet_info(69) = struct(		''name'',			''MIN_POS_UNITS'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MAX_POS_UNITS (0x0047): Set/report the current maximum position of a module movement, in millimeters or degrees.';
			'packet_info(71) = struct(		''name'',			''MAX_POS_UNITS'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MIN_SPEED_UNITS_S (0x0049): Set/report the current minimum speed (i.e. motor start speed), in mm/s or deg/s.';
			'packet_info(73) = struct(		''name'',			''MIN_SPEED_UNITS_S'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MAX_SPEED_UNITS_S (0x0051): Set/report the current maximum speed, in mm/s or deg/s.';
			'packet_info(81) = struct(		''name'',			''MAX_SPEED_UNITS_S'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% ACCEL_UNITS_S2 (0x0053): Set/report the current movement acceleration, in mm/s^2 or deg/s^2^2.';
			'packet_info(83) = struct(		''name'',			''ACCEL_UNITS_S2'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MOTOR_CURRENT (0x0055): Set/report the current motor current setting, in milliamps.';
			'packet_info(85) = struct(		''name'',			''MOTOR_CURRENT'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MAX_MOTOR_CURRENT (0x0057): Set/report the maximum possible motor current, in milliamps.';
			'packet_info(87) = struct(		''name'',			''MAX_MOTOR_CURRENT'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% FW_STALL_DETECTION (0x0059): Set/report the firmware-based stall detection setting, on or off.';
			'packet_info(89) = struct(		''name'',			''FW_STALL_DETECTION'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% HW_STALL_DETECTION (0x005B): Set/report the hardware-based stall detection setting, on or off.';
			'packet_info(91) = struct(		''name'',			''HW_STALL_DETECTION'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% STALL_THRESH (0x005D): Set/report the current stall threshold, 0-4095.';
			'packet_info(93) = struct(		''name'',			''STALL_THRESH'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TRQ_SCALING (0x005F): Set/report the torque count scaling setting, 1x or 8x.';
			'packet_info(95) = struct(		''name'',			''TRQ_SCALING'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TRQ_COUNT (0x0061): Set/report the current torque count, 0-4095.';
			'packet_info(97) = struct(		''name'',			''TRQ_COUNT'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MOTOR_STALL (0x0062): Report a motor stall.';
			'packet_info(98) = struct(		''name'',			''MOTOR_STALL'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	11,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MOTOR_FAULT (0x0063): Report a motor fault, other than a stall (i.e. undervoltage, overcurrent, overtemperature).';
			'packet_info(99) = struct(		''name'',			''MOTOR_FAULT'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% STREAM_PERIOD (0x0065): Set/report the current streaming period, in milliseconds.';
			'packet_info(101) = struct(		''name'',			''STREAM_PERIOD'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% STREAM_ENABLE (0x0067): Enable/disable streaming from the device.';
			'packet_info(103) = struct(		''name'',			''STREAM_ENABLE'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% DISPENSER_READY (0x0090): Report that a dispenser has prepared a reward (i.e. a pellet) for dispensing.';
			'packet_info(144) = struct(		''name'',			''DISPENSER_READY'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% DISPENSER_EMPTY (0x0092): Report that a dispenser is empty or cannot detect an available reward.';
			'packet_info(146) = struct(		''name'',			''DISPENSER_EMPTY'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% MAX_RELOAD_ATTEMPTS (0x0095): Set/report the current maximum number of reload attempts.';
			'packet_info(149) = struct(		''name'',			''MAX_RELOAD_ATTEMPTS'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% NUM_TONES (0x0103): Report the number of queueable tones.';
			'packet_info(259) = struct(		''name'',			''NUM_TONES'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TONE_INDEX (0x0104): Set/report the current tone index.';
			'packet_info(260) = struct(		''name'',			''TONE_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TONE_FREQ (0x0106): Set/report the frequency of the current tone, in Hertz.';
			'packet_info(262) = struct(		''name'',			''TONE_FREQ'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TONE_DUR (0x0108): Set/report the duration of the current tone, in milliseconds.';
			'packet_info(264) = struct(		''name'',			''TONE_DUR'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TONE_VOLUME (0x010A): Set/report the volume of the current tone, normalized from 0 to 1.';
			'packet_info(266) = struct(		''name'',			''TONE_VOLUME'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% NUM_CUE_LIGHTS (0x0182): Report the number of queueable cue lights.';
			'packet_info(386) = struct(		''name'',			''NUM_CUE_LIGHTS'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CUE_LIGHT_INDEX (0x0184): Set/report the current cue light index.';
			'packet_info(388) = struct(		''name'',			''CUE_LIGHT_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CUE_LIGHT_QUEUE_SIZE (0x018C): Set/report the number of queueable cue light stimuli.';
			'packet_info(396) = struct(		''name'',			''CUE_LIGHT_QUEUE_SIZE'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CUE_LIGHT_QUEUE_INDEX (0x018E): Set/report the current cue light queue index.';
			'packet_info(398) = struct(		''name'',			''CUE_LIGHT_QUEUE_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_BITMASK (0x0200): Set/report the current nosepoke status bitmask.';
			'packet_info(512) = struct(		''name'',			''POKE_BITMASK'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_ADC (0x0202): Report the current nosepoke analog reading (returns both the filtered and raw value).';
			'packet_info(514) = struct(		''name'',			''POKE_ADC'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint32''; 2, ''uint16''}},...';
			'								''min_bytes'',	11,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_MINMAX (0x0204): Set/report the minimum and maximum ADC values of the nosepoke infrared sensor history, in ADC ticks.';
			'packet_info(516) = struct(		''name'',			''POKE_MINMAX'',...';
			'								''payload'',		{{1, ''uint8''; 2, ''uint16''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_THRESH_FL (0x0206): Set/report the current nosepoke threshold setting, normalized from 0 to 1.';
			'packet_info(518) = struct(		''name'',			''POKE_THRESH_FL'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_THRESH_ADC (0x0208): Set/report the current nosepoke threshold setting, in ADC ticks.';
			'packet_info(520) = struct(		''name'',			''POKE_THRESH_ADC'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_THRESH_AUTO (0x020A): Set/report the current nosepoke auto-thresholding setting (0 = fixed, 1 = autoset).';
			'packet_info(522) = struct(		''name'',			''POKE_THRESH_AUTO'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_INDEX (0x020D): Set/report the current nosepoke index for multi-nosepoke modules.';
			'packet_info(525) = struct(		''name'',			''POKE_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_MIN_RANGE (0x020F): Set/report the minimum signal range for positive detection with the current nosepoke, in ADC ticks.';
			'packet_info(527) = struct(		''name'',			''POKE_MIN_RANGE'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% POKE_LOWPASS_CUTOFF (0x0211): Set/report the current nosepoke sensor low-pass filter cutoff frequency, in Hz.';
			'packet_info(529) = struct(		''name'',			''POKE_LOWPASS_CUTOFF'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_BITMASK (0x0270): Set/report the current capacitive sensor status bitmask.';
			'packet_info(624) = struct(		''name'',			''CAPSENSE_BITMASK'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_INDEX (0x0272): Set/report the current capacitive sensor index.';
			'packet_info(626) = struct(		''name'',			''CAPSENSE_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_SENSITIVITY (0x0274): Set/report the current capacitive sensor sensitivity setting, normalized from 0 to 1.';
			'packet_info(628) = struct(		''name'',			''CAPSENSE_SENSITIVITY'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_VALUE (0x0280): Report the current capacitance sensor reading, in ADC ticks or clock cycles.';
			'packet_info(640) = struct(		''name'',			''CAPSENSE_VALUE'',...';
			'								''payload'',		{{1, ''uint32''; 2, ''uint8''; 2, ''uint16''}},...';
			'								''min_bytes'',	12,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_MINMAX (0x0282): Report the minimum and maximum values of the current capacitive sensor''s history.';
			'packet_info(642) = struct(		''name'',			''CAPSENSE_MINMAX'',...';
			'								''payload'',		{{1, ''uint8''; 2, ''uint16''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_MIN_RANGE (0x0284): Set/report the minimum signal range for positive detection with the current capacitive sensor.';
			'packet_info(644) = struct(		''name'',			''CAPSENSE_MIN_RANGE'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_THRESH_FIXED (0x0286): Set/report a fixed threshold for the current capacitive sensor, in ADC ticks or clock cycles.';
			'packet_info(646) = struct(		''name'',			''CAPSENSE_THRESH_FIXED'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_THRESH_AUTO (0x0288): Set/report the current capacitive sensor auto-thresholding setting (0 = fixed, 1 = autoset <default>).';
			'packet_info(648) = struct(		''name'',			''CAPSENSE_THRESH_AUTO'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_RESET_TIMEOUT (0x028A): Set/report the current capacitive sensor reset timeout duration, in milliseconds (0 = no time-out reset).';
			'packet_info(650) = struct(		''name'',			''CAPSENSE_RESET_TIMEOUT'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_SAMPLE_SIZE (0x028C): Set/report the current capacitive sensor repeated measurement sample size.';
			'packet_info(652) = struct(		''name'',			''CAPSENSE_SAMPLE_SIZE'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_HIGHPASS_CUTOFF (0x0292): Set/report the current capacitive sensor high-pass filter cutoff frequency, in Hz.';
			'packet_info(658) = struct(		''name'',			''CAPSENSE_HIGHPASS_CUTOFF'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CAPSENSE_LOWPASS_CUTOFF (0x0296): Set/report the current capacitive sensor low-pass filter cutoff frequency, in Hz.';
			'packet_info(662) = struct(		''name'',			''CAPSENSE_LOWPASS_CUTOFF'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% THERM_PIXELS_FP62 (0x0303): Report a thermal pixel image as a fixed-point 6/2 type (6 bits for the unsigned integer part, 2 bits for the decimal part), in units of Celcius. This allows temperatures from 0 to 63.75 C.';
			'packet_info(771) = struct(		''name'',			''THERM_PIXELS_FP62'',...';
			'								''payload'',		{{1, ''uint32''; 1027, ''uint8''}},...';
			'								''min_bytes'',	1033,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% THERM_XY_PIX (0x0311): Report the current thermal hotspot x-y position, in units of pixels.';
			'packet_info(785) = struct(		''name'',			''THERM_XY_PIX'',...';
			'								''payload'',		{{1, ''uint32''; 3, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	13,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OPTICAL_FLOW_XY (0x0401): Report the current x- and y-coordinates from the currently-selected optical flow sensor, as 32-bit integers.';
			'packet_info(1025) = struct(		''name'',			''OPTICAL_FLOW_XY'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 2, ''int32''}},...';
			'								''min_bytes'',	15,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OPTICAL_FLOW_DELTA_XY (0x0403): Report the current change in x- and y-coordinates from the currently-selected optical flow sensor, as 32-bit integers.';
			'packet_info(1027) = struct(		''name'',			''OPTICAL_FLOW_DELTA_XY'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 2, ''int32''}},...';
			'								''min_bytes'',	15,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OPTICAL_FLOW_DELTA_3VEC (0x0405): Report the current change in value from the three selected optical flow vectors, as 16-bit integers.';
			'packet_info(1029) = struct(		''name'',			''OPTICAL_FLOW_DELTA_3VEC'',...';
			'								''payload'',		{{1, ''uint32''; 3, ''int32''}},...';
			'								''min_bytes'',	18,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TTL_INDEX (0x0501): Set/report the current TTL I/O index.';
			'packet_info(1281) = struct(		''name'',			''TTL_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TTL_PULSE_OFF_VAL (0x0507): Set/report the current TTL pulse "off" value.';
			'packet_info(1287) = struct(		''name'',			''TTL_PULSE_OFF_VAL'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TTL_PULSE_ON_VAL (0x0508): Set/report the current TTL pulse "on" value.';
			'packet_info(1288) = struct(		''name'',			''TTL_PULSE_ON_VAL'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TTL_XINT_THRESH (0x050B): Set/report the current TTL input pseudo-interrupt threshold.';
			'packet_info(1291) = struct(		''name'',			''TTL_XINT_THRESH'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TTL_DIGITAL_BITMASK (0x0510): Report the current TTL digital status bitmask.';
			'packet_info(1296) = struct(		''name'',			''TTL_DIGITAL_BITMASK'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% TTL_AIN (0x0513): Report the specified TTL I/O''s analog input value.';
			'packet_info(1299) = struct(		''name'',			''TTL_AIN'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint32''; 1, ''single''}},...';
			'								''min_bytes'',	11,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_DUR (0x4000): Set/report the current vibration pulse duration, in microseconds.';
			'packet_info(16384) = struct(	''name'',			''VIB_DUR'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_IPI (0x4002): Set/report the current vibration train onset-to-onset inter-pulse interval, in microseconds.';
			'packet_info(16386) = struct(	''name'',			''VIB_IPI'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_N_PULSE (0x4004): Set/report the current vibration train duration, in number of pulses.';
			'packet_info(16388) = struct(	''name'',			''VIB_N_PULSE'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_GAP (0x4006): Set/report the current vibration train skipped pulses starting and stopping index.';
			'packet_info(16390) = struct(	''name'',			''VIB_GAP'',...';
			'								''payload'',		{{2, ''uint16''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_MASK_ENABLE (0x400C): Enable/disable vibration tone masking (0 = disabled, 1 = enabled).';
			'packet_info(16396) = struct(	''name'',			''VIB_MASK_ENABLE'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_MASK_TONE_INDEX (0x400D): Set/report the current tone repertoire index for the masking tone.';
			'packet_info(16397) = struct(	''name'',			''VIB_MASK_TONE_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_TASK_MODE (0x400F): Set/report the current vibration task mode (1 = BURST, 2 = GAP).';
			'packet_info(16399) = struct(	''name'',			''VIB_TASK_MODE'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% VIB_INDEX (0x4011): Set/report the current vibration motor/actuator index.';
			'packet_info(16401) = struct(	''name'',			''VIB_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% CENTER_OFFSET (0x412A): Set/report the center-to-slot detector offset, in micrometers.';
			'packet_info(16682) = struct(	''name'',			''CENTER_OFFSET'',...';
			'								''payload'',		{{1, ''uint16''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% RECENTER_COMPLETE (0x4133): Indicate that the handle is recentered.';
			'packet_info(16691) = struct(	''name'',			''RECENTER_COMPLETE'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% BAUDRATE_TEST (0x7463): Send/receive a baud rate test packet (uint8 values 0-x, in order).';
			'packet_info(29795) = struct(	''name'',			''BAUDRATE_TEST'',...';
			'								''payload'',		{{256, ''uint8''}},...';
			'								''min_bytes'',	258,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% REPORT_BAUDRATE (0x7465): Report the current baud rate (in Hz).';
			'packet_info(29797) = struct(	''name'',			''REPORT_BAUDRATE'',...';
			'								''payload'',		{{1, ''uint32''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_VAL_ADC (0xAA07): Report the current force/loadcell value, in ADC ticks (uint16).';
			'packet_info(43527) = struct(	''name'',			''LOADCELL_VAL_ADC'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	9,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_INDEX (0xAA08): Set/report the current loadcell/force sensor index.';
			'packet_info(43528) = struct(	''name'',			''LOADCELL_INDEX'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_VAL_GM (0xAA0B): Report the current force/loadcell value, in units of grams (float).';
			'packet_info(43531) = struct(	''name'',			''LOADCELL_VAL_GM'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	11,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_CAL_BASELINE (0xAA0D): Set/report the current loadcell/force calibration baseline, in ADC ticks (float).';
			'packet_info(43533) = struct(	''name'',			''LOADCELL_CAL_BASELINE'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_CAL_SLOPE (0xAA0F): Set/report the current loadcell/force calibration slope, in grams per ADC tick (float).';
			'packet_info(43535) = struct(	''name'',			''LOADCELL_CAL_SLOPE'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_DIGPOT_BASELINE (0xAA11): Set/report the current loadcell/force baseline-adjusting digital potentiometer setting, scaled 0-1 (float).';
			'packet_info(43537) = struct(	''name'',			''LOADCELL_DIGPOT_BASELINE'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_VAL_DGM (0xAA13): Report the current force/loadcell value, in units of decigrams (int16).';
			'packet_info(43539) = struct(	''name'',			''LOADCELL_VAL_DGM'',...';
			'								''payload'',		{{1, ''uint32''; 1, ''uint8''; 1, ''int16''}},...';
			'								''min_bytes'',	9,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% LOADCELL_GAIN (0xAA15): Set/report the current force/loadcell gain setting (float).';
			'packet_info(43541) = struct(	''name'',			''LOADCELL_GAIN'',...';
			'								''payload'',		{{1, ''single''}},...';
			'								''min_bytes'',	6,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% PASSTHRU_UP (0xBCDF): Route the immediately following block upstream, typically to the controller or computer.';
			'packet_info(48351) = struct(	''name'',			''PASSTHRU_UP'',...';
			'								''payload'',		{{1, ''uint8''; NaN, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% REQ_OTMP_IOUT (0xBCF0): Request the OmniTrak Module Port (OTMP) output current for the specified port, in milliamps.';
			'packet_info(48368) = struct(	''name'',			''REQ_OTMP_IOUT'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OTMP_IOUT (0xBCF1): Report the OmniTrak Module Port (OTMP) output current for the specified port, in milliamps.';
			'packet_info(48369) = struct(	''name'',			''OTMP_IOUT'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''single''}},...';
			'								''min_bytes'',	7,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OTMP_ACTIVE_PORTS (0xBCF3): Report a bitmask indicating which OmniTrak Module Ports (OTMPs) are active based on current draw.';
			'packet_info(48371) = struct(	''name'',			''OTMP_ACTIVE_PORTS'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% REQ_OTMP_HIGH_VOLT (0xBCF4): Request the current high voltage supply setting for the specified OmniTrak Module Port (0 = off <default>, 1 = high voltage enabled).';
			'packet_info(48372) = struct(	''name'',			''REQ_OTMP_HIGH_VOLT'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OTMP_HIGH_VOLT (0xBCF5): Set/report the current high voltage supply setting for the specified OmniTrak Module Port (0 = off <default>, 1 = high voltage enabled).';
			'packet_info(48373) = struct(	''name'',			''OTMP_HIGH_VOLT'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OTMP_OVERCURRENT_PORTS (0xBCF7): Report a bitmask indicating which OmniTrak Module Ports (OTMPs) are in overcurrent shutdown.';
			'packet_info(48375) = struct(	''name'',			''OTMP_OVERCURRENT_PORTS'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% REQ_OTMP_CHUNK_SIZE (0xBCF9): Request the current serial "chunk" size required for transmission from the specified OmniTrak Module Port (OTMP), in bytes.';
			'packet_info(48377) = struct(	''name'',			''REQ_OTMP_CHUNK_SIZE'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OTMP_CHUNK_SIZE (0xBCFA): Set/report the current serial "chunk" size required for transmission from the specified OmniTrak Module Port (OTMP), in bytes.';
			'packet_info(48378) = struct(	''name'',			''OTMP_CHUNK_SIZE'',...';
			'								''payload'',		{{2, ''uint8''}},...';
			'								''min_bytes'',	4,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% REQ_OTMP_PASSTHRU_TIMEOUT (0xBCFB): Request the current serial "chunk" timeout for the specified OmniTrak Module Port (OTMP), in microseconds.';
			'packet_info(48379) = struct(	''name'',			''REQ_OTMP_PASSTHRU_TIMEOUT'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% OTMP_PASSTHRU_TIMEOUT (0xBCFC): Set/report the current serial "chunk" timeout for the specified OmniTrak Module Port (OTMP), in microseconds.';
			'packet_info(48380) = struct(	''name'',			''OTMP_PASSTHRU_TIMEOUT'',...';
			'								''payload'',		{{1, ''uint8''; 1, ''uint16''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% BLE_CONNECTED (0xC003): Indicate that a Bluetooth Low Energy (BLE) device connection is active (0 = closed/inactive, 1 = active).';
			'packet_info(49155) = struct(	''name'',			''BLE_CONNECTED'',...';
			'								''payload'',		{{1, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	true);';
			'';
			'';
			'% BLE_CHAR_NOTIFY (0xC006): Report a Bluetooth Low Energy (BLE) device characteristic notification value.';
			'packet_info(49158) = struct(	''name'',			''BLE_CHAR_NOTIFY'',...';
			'								''payload'',		{{NaN, ''uint8''}},...';
			'								''min_bytes'',	3,...';
			'								''fixed_size'',	false);';
			'';
			'';
			'% BLE_DEVICE_NAME (0xC008): Report the address, local name, and service UUID of an available BLE device.';
			'packet_info(49160) = struct(	''name'',			''BLE_DEVICE_NAME'',...';
			'								''payload'',		{{NaN, ''char''; NaN, ''char''; NaN, ''char''}},...';
			'								''min_bytes'',	5,...';
			'								''fixed_size'',	false);';
		};

	case 'Vulintus_OTSC_Empty_Process'
		txt =	{
			'function Vulintus_OTSC_Empty_Process(block_name, varargin)';
			'';
			'%';
			'% Vulintus_OTSC_Empty_Process.m';
			'% ';
			'%   copyright 2025, Vulintus, Inc.';
			'%';
			'%   VULINTUS_OTSC_EMPTY_PROCESS is an intentional do-nothing function for';
			'%   use as a placeholder process function to execute when packets are';
			'%   received through Vulintus'' OmniTrak Serial Communication (OTSC) ';
			'%   protocol.';
			'%   ';
			'%   UPDATE LOG:';
			'%   2025-04-09 - Drew Sloan - Function first created.';
			'%';
			'';
			'fprintf(1,''No process function assigned for OTSC block "%s".\n'',...';
			'    block_name);                                                            %Show that no process function is assigned for this block.';
		};

	case 'Vulintus_OTSC_Parse_Packet'
		txt =	{
			'function bytes_required = Vulintus_OTSC_Parse_Packet(buffer, src, packet, process_fcn)';
			'';
			'% Vulintus_OTSC_Parse_Packet.m';
			'%';
			'%   copyright 2025, Vulintus, Inc.';
			'%';
			'%   VULINTUS_OTSC_PARSE_PACKET converts the bytes of an incoming data';
			'%   packet using the Vulintus OmniTrak Serial Communication (OTSC) into';
			'%   the expected formats (''int8'', ''uint8'', ''int16'', ''uint16'', ''int32'', ';
			'%   ''uint32'', ''uint64'', ''single'', or ''double'') specified in an optional ';
			'%   "packet" cell array. If the number of values in the expected data is ';
			'%   set to NaN, it will read the first byte of the reply following the OTSC';
			'%   code and use that value as the number of expected values.';
			'%';
			'%   UPDATE LOG:';
			'%   2025-04-10 - Drew Sloan - Function first created, adapted from';
			'%                             "Vulintus_OTSC_Transaction.m"';
			'%';
			'';
			'if buffer.count < packet.min_bytes                                          %If buffer doesn''t have enough bytes.';
			'    bytes_required = packet.min_bytes;                                      %Send back the number of bytes required...';
			'    return                                                                  %Skip the rest of the function.';
			'end';
			'';
			'type_size = @(data_type)Vulintus_Return_Data_Type_Size(data_type);          %Create a shortened pointer to the data type size toolbox functions.';
			'';
			'data = cell(1,size(packet.payload,1));                                      %Create a cell array to hold the data.';
			'if packet.fixed_size                                                        %If the packet info is a fixed size...';
			'    buffer.clear(2);                                                        %Clear the OTSC code from the buffer.';
			'    for i = 1:size(packet.payload,1)                                        %Step through each requested data type.';
			'        data{i} = buffer.read(packet.payload{i,1},...';
			'            packet.payload{i,2});                                           %Read each data type out of the buffer.';
			'    end    ';
			'else                                                                        %Otherwise, if the packet info isn''t a fixed size...';
			'    packet_N = packet.min_bytes;                                            %Update the expected number of bytes in the data packet.';
			'    temp_buffer = buffer.peek(packet_N);                                    %Peek at the bytes of the packet.';
			'    byte_i = 2;                                                             %Start counting after the 3rd byte.';
			'    for i = 1:size(packet.payload,1)                                        %Step through each requested data type.';
			'        if isnan(packet.payload{i,1})                                       %If the number of expected elements is NaN...';
			'            byte_i = byte_i + 1;                                            %Increment the byte counter.';
			'            packet.payload{i,1} = temp_buffer(byte_i);                      %Grab the number of rexpected values from the next byte.            ';
			'        end';
			'        n_bytes = packet.payload{i,1}*type_size(packet.payload{i,2});       %Calculate byte size of the expected values.';
			'        packet_N = byte_i + n_bytes;                                        %Calculate the new number or required bytes.';
			'        if buffer.count < packet_N                                          %If the buffer doesn''t have all the samples.';
			'            bytes_required = packet_N;                                      %Send back the number of bytes required...';
			'            return                                                          %Skip the rest of the function.';
			'        end';
			'        temp_buffer = buffer.peek(packet_N);                                %Peek again at the bytes of the packet.';
			'        if packet.payload{i,1} > 0                                          %If a nonzero count is requested...';
			'            data{i} = temp_buffer(byte_i + (1:n_bytes));                    %Read in the expected number of bytes.';
			'            switch packet.payload{i,2}                                      %Switch between the different data types.';
			'                case ''char''                                                 %For character arrays...';
			'                    data{i} = char(data{i});                                %Convert the bytes to characters.';
			'                otherwise                                                   %For all other data types...';
			'                    data{i} = typecast(data{i},packet.payload{i,2});        %Cast the data to the expected type.';
			'            end            ';
			'            byte_i = byte_i + n_bytes;                                      %Increment the byte counter.';
			'        end';
			'    end';
			'    buffer.clear(packet_N);                                                 %Clear the bytes out of the buffer.';
			'end';
			'';
			'bytes_required = 0;                                                         %Return a zero to indicate that the packet was complete.';
			'';
			'if ~isempty(process_fcn)                                                    %If a process function was set...';
			'    process_fcn(src, data{:});                                              %Send the data and the source index to the process function.';
			'end';
		};

	case 'Vulintus_OTSC_Passthrough_Commands'
		txt =	{
			'function [pass_down_cmd, pass_up_cmd] = Vulintus_OTSC_Passthrough_Commands';
			'';
			'%	Vulintus_OTSC_Passthrough_Commands.m';
			'%';
			'%	copyright, Vulintus, Inc.';
			'%';
			'%	OmniTrak Serial Communication (OTSC) library.';
			'%	Simplified function for loading just the passthrough block codes.';
			'%';
			'%	Library documentation:';
			'%	https://github.com/Vulintus/OmniTrak_Serial_Communication';
			'%';
			'%	This function was programmatically generated: 2025-06-09, 07:46:00 (UTC)';
			'%';
			'';
			'pass_down_cmd = 48350;		%Route the immediately following block downstream to the specified port or VPB device.';
			'pass_up_cmd = 48351;		%Route the immediately following block upstream, typically to the controller or computer.';
		};

	case 'Vulintus_OTSC_Transaction'
		txt =	{
			'function varargout = Vulintus_OTSC_Transaction(serialcon,cmd,varargin)';
			'';
			'% Vulintus_Serial_Request.m';
			'%';
			'%   copyright 2024, Vulintus, Inc.';
			'%';
			'%   VULINTUS_OTSC_TRANSACTION sends an OTSC code ("cmd") followed by any';
			'%   specified accompanying data ("data"), and then can wait for a reply';
			'%   consisting of a the specified number of values in the specified format ';
			'%   (''int8'', ''uint8'', ''int16'', ''uint16'', ''int32'', ''uint32'', ''uint64'',...';
			'%   ''single'', or ''double''), unless no requested reply ("req") is expected ';
			'%   or unless told not to wait ("nowait"). If the number of values in the';
			'%   requested data is set to NaN, it will read the first byte of the reply';
			'%   following the OTSC code use that value as the number of expected values';
			'%   in the reply.';
			'%';
			'%   UPDATE LOG:';
			'%   2024-06-07 - Drew Sloan - Consolidated "Vulintus_Serial_Send",';
			'%                             "Vulintus_Serial_Request", and ';
			'%                             "Vulintus_Serial_Request_Bytes" into a';
			'%                             single function.';
			'%   2024-08-29 - Drew Sloan - Added handling so that a passthrough target';
			'%                             equal to zero cancels the passthrough ';
			'%                             command.';
			'%   2024-11-09 - Drew Sloan - Added a slowed sending option for large data';
			'%                             packets that might overrun the target';
			'%                             device''s read buffer.';
			'%   2024-12-04 - Drew Sloan - Fixed bug that would flush the serial input';
			'%                             buffer for non-returning commands during';
			'%                             streaming.';
			'%   2025-01-22 - Drew Sloan - Added error reporting for when an optional';
			'%                             input argument is unrecognized.';
			'%';
			'';
			'';
			'wait_for_reply = true;                                                      %Wait for the reply by default.';
			'passthrough = false;                                                        %Assume this is not a passthrough command.';
			'data = {};                                                                  %Assume that no code-folling data will be sent.';
			'req = {};                                                                   %Assume that no reply will be requested.';
			'slow_send = false;                                                          %Assume we''ll send the data at the fastest speed.';
			'slow_pause = 0.0001;                                                        %Set the slow send pause duration.';
			'';
			'i = 1;                                                                      %Initialize a input variable counter.';
			'while i <= numel(varargin)                                                  %Step through all of the variable input arguments.  ';
			'    if ischar(varargin{i})                                                  %If the input is characters...';
			'        switch lower(varargin{i})                                           %Switch between recognized arguments.';
			'            case ''nowait''                                                   %If the user specified not to wait for the reply...';
			'                wait_for_reply = false;                                     %Don''t wait for the reply.';
			'                i = i + 1;                                                  %Increment the variable counter.';
			'            case ''passthrough''                                              %If this is a passthrough command..';
			'                passthrough = true;                                         %Set the passthrough flag to true.';
			'                pass_target = varargin{i+1};                                %Grab the passthrough target.';
			'                i = i + 2;                                                  %Increment the variable counter by two.';
			'            case ''data''                                                     %If OTSC code-following data is specified...';
			'                data = varargin{i+1};                                       %Grab the code-following data.';
			'                i = i + 2;                                                  %Increment the variable counter by two.';
			'            case ''reply''                                                    %If an expected reply is specified...';
			'                req = varargin{i+1};                                        %Grab the requested data ounts and types.';
			'                i = i + 2;                                                  %Increment the variable counter by two.';
			'            case ''slow''                                                     %If a slow sending speed is specified...';
			'                slow_send = true;                                           %Set the slow send flag.';
			'                i = i + 1;                                                  %Increment the variable counter.';
			'            otherwise                                                       %For any unrecognized argument...';
			'                error(''ERROR IN %s: Unrecognized input argument''''%s''''!'',...';
			'                    upper(mfilename),lower(varargin{i}));                   %Show an error.';
			'        end';
			'    else                                                                    %Otherwise...';
			'        error(''ERROR IN %s: Unrecognized input type''''%s''''!'',...';
			'            upper(mfilename),class(varargin{i}));                           %Show an error.';
			'    end';
			'end';
			'';
			'if wait_for_reply && isempty(req)                                           %If we''re waiting for a reply, but none is expected...';
			'    wait_for_reply = false;                                                 %Don''t wait for a reply.';
			'end';
			'';
			'varargout = cell(1,size(req,1)+1);                                          %Create a cell array to hold the variable output arguments.';
			'';
			'vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon);               %Load the basic serial functions for either "serialport" or "serial".';
			'type_size = @(data_type)Vulintus_Return_Data_Type_Size(data_type);          %Create a shortened pointer to the data type size toolbox functions.';
			'';
			'if vulintus_serial.bytes_available() > 0 && wait_for_reply                  %If there''s currently any data on the serial line.';
			'    vulintus_serial.flush();                                                %Flush any existing bytes off the serial line.';
			'end';
			'';
			'if passthrough && pass_target == 0                                          %If passthrough is specified, but the target index is zero..';
			'    passthrough = false;                                                    %Ignore the passthrough command.';
			'end';
			'';
			'data_N = zeros(size(data,1),1);                                             %Count the byte size of each data type to be sent.';
			'for i = 1:size(data,1)                                                      %Step through each data type to be sent.';
			'    byte_size = type_size(data{i,2});                                       %Grab the byte size of the data type.';
			'    data_N(i) = numel(data{i,1})*byte_size;                                 %Add the number of expected bytes to the total.';
			'end';
			'';
			'if passthrough                                                              %If the passthrough command was included...';
			'    [pass_down_cmd, pass_up_cmd] = Vulintus_OTSC_Passthrough_Commands;      %Grab the passthrough commands.';
			'    vulintus_serial.write(pass_down_cmd,''uint16'');                          %Write the fixed-length passthrough command.';
			'    vulintus_serial.write(pass_target,''uint8'');                             %Write the target port index and a zero to indicate the command comes from the computer.';
			'    vulintus_serial.write(sum(data_N) + 2,''uint8'');                         %Write the number of subsequent bytes to pass.';
			'end';
			'';
			'vulintus_serial.write(cmd,''uint16'');                                        %Write the command to the serial line.';
			'for i = 1:size(data,1)                                                      %Step through each row of the code-following data.';
			'    if slow_send || rem(data_N(i),64) == 0                                  %If we''re slowing the send speed or the data packet is a multiple of 64...';
			'        for j = 1:numel(data{i,1})                                          %Step through the elements of data.';
			'            vulintus_serial.write(data{i,1}(j),data{i,2});                  %Write the data to the serial line individually.';
			'            pause(slow_pause*type_size(data{i,2}));                         %Pause to let the target device''s read buffer catch up.';
			'        end';
			'    else                                                                    %Otherwise...';
			'        vulintus_serial.write(data{i,1},data{i,2});                         %Write the data to the serial line as a chunk.';
			'    end';
			'end';
			'';
			'if ~isempty(req) && wait_for_reply                                          %If we''re waiting for the reply.';
			'';
			'    req_N = 2;                                                              %Set the expected size of the data packet.';
			'    reply_bytes = zeros(size(req,1),1);                                     %Create a matrix to hold the number of bytes for each requested type.';
			'    for i = 1:size(req,1)                                                   %Step through each requested data type.';
			'        if ~isnan(req{i,1})                                                 %If the number of requested elements isn''t NaN...            ';
			'            byte_size = type_size(req{i,2});                                %Grab the byte size of the requested data type.';
			'            reply_bytes(i) = req{i,1}*byte_size;                            %Set the number of bytes expected for this requested data type.';
			'        else                                                                %Otherwise, if the number of elements is NaN.';
			'           reply_bytes(i) = 1;                                              %Add one byte to the number expected data packet size.';
			'        end';
			'    end';
			'    req_N = req_N + sum(reply_bytes);                                       %Sum the number of bytes for each requested data type.';
			'    ';
			'    timeout = 1.0;                                                          %Set a one second time-out for the following loop.';
			'    timeout_timer = tic;                                                    %Start a stopwatch.';
			'    while toc(timeout_timer) < timeout && ...';
			'            vulintus_serial.bytes_available() <  req_N                      %Loop for 1 seconds or until the expected reply shows up on the serial line.';
			'        pause(0.005);                                                       %Pause for 5 milliseconds.';
			'    end';
			'';
			'    if vulintus_serial.bytes_available() < req_N                            %If there''s not at least the expected number of bytes on the serial line...';
			'        hex_code = dec2hex(cmd,4);                                          %Convert the command code to hex.';
			'        if passthrough                                                      %If this was a passthrough command...';
			'            hex_code = sprintf(''%s = (passthrough->%1.0f)'',pass_target);    %Add the passthrough target to the command code.';
			'        end';
			'        cprintf([1,0.5,0],[''Vulintus_OTSC_Transaction Timeout! OTSC ''...';
			'            ''code 0x%s: %1.0f of %1.0f requested bytes returned.\n''],...';
			'            hex_code, vulintus_serial.bytes_available(), req_N);            %Indicate a timeout occured.';
			'        vulintus_serial.flush();                                            %Flush any remaining bytes off the serial line.';
			'        return                                                              %Skip execution of the rest of the function.';
			'    end';
			'';
			'    if ~passthrough                                                         %If this wasn''t a passthrough request...        ';
			'';
			'        code = vulintus_serial.read(1,''uint16'');                            %Read in the unsigned 16-bit integer block code.';
			'        req_N = req_N - 2;                                                  %Update the expected number of bytes in the data packet.';
			'        for i = 1:size(req,1)                                               %Step through each requested data type.';
			'            if isnan(req{i,1})                                              %If the number of requested elements is NaN...';
			'                req{i,1} = vulintus_serial.read(1,''uint8'');                 %Set the number of requested elements to the next byte.';
			'                reply_bytes(i) = req{i,1}*type_size(req{i,2});              %Update the number of bytes expected for this data typ.';
			'                req_N = req_N + reply_bytes(i) - 1;                         %Update the expected number of bytes in the data packet.';
			'            end';
			'            while toc(timeout_timer) < timeout && ...';
			'                    vulintus_serial.bytes_available() < req_N               %Loop for 1 seconds or until the expected reply shows up on the serial line.';
			'                pause(0.001);                                               %Pause for 1 millisecond.';
			'            end';
			'            if vulintus_serial.bytes_available() < req_N                    %If there''s not at least the expected number of bytes on the serial line...       ';
			'                vulintus_serial.flush();                                    %Flush any remaining bytes off the serial line.';
			'                return                                                      %Skip execution of the rest of the function.';
			'            end';
			'            if req{i,1} > 0                                                 %If a nonzero count is requested...';
			'                varargout{i} = vulintus_serial.read(req{i,1},req{i,2});     %Read in the requested values as the specified data type.';
			'                if strcmpi(req{i,2},''char'') && ~ischar(varargout{i})        %If the output is supposed to be a character array and it''s not.';
			'                    varargout{i} = reshape(char(varargout{i}),1,[]);        %Convert the output to a character array.';
			'                end';
			'            end';
			'            req_N = req_N - reply_bytes(i);                                 %Upate the number of expected bytes in the data packet.';
			'        end';
			'        varargout{size(req,1)+1} = code;                                    %Return the reply OTSC code as the last output argument.';
			'';
			'    else                                                                    %Otherwise, if this was a passthrough request...';
			'';
			'        code = [];                                                          %Create an empty matrix to hold the reply OTSC code. ';
			'        buffer = uint8(zeros(1,1024));                                      %Create a buffer to hold the received bytes.';
			'        buff_i = 0;                                                         %Create a buffer index.';
			'        read_N = 0;                                                         %Keep track of the number of bytes to read.';
			'        i = 1;                                                              %Create a reply type index.';
			'        timeout = 0.1;                                                      %Set a 100 millisecond time-out for the following loop.';
			'        timeout_timer = tic;                                                %Start a stopwatch.        ';
			'        while toc(timeout_timer) < timeout && req_N > 0                     %Loop until the time-out duration has passed.';
			'';
			'            if vulintus_serial.bytes_available()                            %If there''s serial bytes available...';
			'                if read_N                                                   %If there''s still bytes to read...';
			'                    n_bytes = vulintus_serial.bytes_available();            %Grab the number of bytes available on the serial line.';
			'                    n_bytes = min(n_bytes, read_N);                         %Read in the smaller of the number of bytes available or the bytes remaining in the block.';
			'                    if pass_source == pass_target                           %If these bytes come from the target.';
			'                        buffer(buff_i + (1:n_bytes)) = ...';
			'                            vulintus_serial.read(n_bytes,''uint8'');          %Read in the bytes.';
			'                        buff_i = buff_i + n_bytes;                          %Increment the buffer index.                                     ';
			'                    else                                                    %Otherwise...';
			'                        vulintus_serial.read(n_bytes,''uint8'');              %Read in and ignore the bytes.';
			'                    end';
			'                    read_N = read_N - n_bytes;                              %Decrement the bytes left to read.';
			'                elseif vulintus_serial.bytes_available() >= 5               %Otherwise, if there''s at least 5 bytes on the serial line...';
			'                    passthru_code = vulintus_serial.read(1,''uint16'');       %Read in the unsigned 16-bit integer block code.';
			'                    if passthru_code ~= pass_up_cmd                         %If the block code isn''t for an upstream passthrough...';
			'                        vulintus_serial.flush();                            %Flush any remaining bytes off the serial line.';
			'                        return                                              %Skip the rest of the function.';
			'                    end';
			'                    pass_source = vulintus_serial.read(1,''uint8'');          %Read in the unsigned 8-bit source ID.';
			'                    read_N = vulintus_serial.read(1,''uint16'');              %Read in the unsigned 16-bit number of bytes.';
			'                end';
			'                timeout_timer = tic;                                        %Restart the stopwatch. ';
			'            end';
			'';
			'            if isempty(code)                                                %If the OTSC reply code hasn''t been read yet...';
			'                if buff_i >= 2                                              %If at least two bytes have been read into the buffer...';
			'                    code = typecast(buffer(1:2),''uint16'');                  %Read the reply OTSC from the buffer.';
			'                    if buff_i > 2                                           %If there''s more bytes left in the buffer.';
			'                        buffer(1:buff_i-2) = buffer(3:buff_i);              %Shift the values in the buffer.';
			'                    end';
			'                    buff_i = buff_i - 2;                                    %Decrement the buffer index.';
			'                    req_N = req_N - 2;                                      %Update the expected number of bytes in the data packet.';
			'                end';
			'            elseif isnan(req{i,1}) && buff_i >= 1                           %If the number of requested elements is NaN...';
			'                req{i,1} = buffer(1);                                       %Set the number of requested elements to the next byte.                            ';
			'                reply_bytes(i) = req{i,1}*type_size(req{i,2});              %Update the number of bytes expected for this data typ.';
			'                if buff_i > 1                                               %If there''s more bytes left in the buffer.';
			'                    buffer(1:buff_i-1) = buffer(2:buff_i);                  %Shift the values in the buffer.';
			'                end';
			'                buff_i = buff_i - 1;                                        %Decrement the buffer index.';
			'                req_N = req_N + reply_bytes(i) - 1;                         %Update the expected number of bytes in the data packet.';
			'            elseif buff_i >= reply_bytes(i) && req{i,1} > 0                 %If the buffer contains all of the next requested data type...';
			'                if strcmpi(req{i,2},''char'')                                 %If we''re reading characters...';
			'                    varargout{i} = ...';
			'                        char(buffer(1:reply_bytes(i)));                     %Convert the bytes to characters.';
			'                else                                                        %Otherwise...';
			'                    varargout{i} = ...';
			'                        typecast(buffer(1:reply_bytes(i)),...';
			'                        req{i,2});                                          %Typecast the bytes from the buffer to the requested type.';
			'                end';
			'                if buff_i > reply_bytes(i)                                  %If there''s more bytes left in the buffer.';
			'                    buffer(1:buff_i-reply_bytes(i)) = ...';
			'                        buffer(reply_bytes(i) + 1:buff_i);                  %Shift the values in the buffer.';
			'                end';
			'                buff_i = buff_i - reply_bytes(i);                           %Decrement the buffer index.';
			'                req_N = req_N - reply_bytes(i);                             %Upate the number of expected bytes in the data packet.';
			'                i = i + 1;                                                  %Increment the data type index.';
			'            elseif req{i,1} == 0                                            %If zero bytes are being returned...';
			'                i = i + 1;                                                  %Increment the data type index.';
			'            end       ';
			'';
			'            pause(0.001);                                                   %Pause for 1 millisecond.';
			'        end';
			'        if req_N                                                            %If bytes were left unread...';
			'            fprintf(1,''Vulintus_OTSC_Transaction Timeout!'');                %Indicate a timeout occured.';
			'        end';
			'        varargout{size(req,1)+1} = code;                                    %Return the reply OTSC code as the last output argument.';
			'';
			'    end';
			'';
			'    vulintus_serial.flush();                                                %Flush any remaining bytes off the serial line.';
			'end';
		};

	case 'Vulintus_Serial_Basic_Functions'
		txt =	{
			'function vulintus_serial = Vulintus_Serial_Basic_Functions(serialcon)';
			'';
			'%Vulintus_Serial_Basic_Functions.m - Vulintus, Inc., 2024';
			'%';
			'%   VULINTUS_SERIAL_BASIC_FUNCTIONS creates a function structure including';
			'%   the basic read, write, bytes available, and flush functions for either ';
			'%   a ''serialport'' or ''serial'' class object.';
			'%';
			'%   UPDATE LOG:';
			'%   2024-06-06 - Drew Sloan - Function first created.';
			'%';
			'';
			'';
			'vulintus_serial = struct;                                                   %Create a structure.';
			'';
			'switch class(serialcon)                                                     %Switch between the types of serial connections.';
			'';
			'    case ''internal.Serialport''                                              %Newer serialport functions.';
			'        vulintus_serial.bytes_available = @serialcon.NumBytesAvailable;     %Number of bytes available.';
			'        vulintus_serial.flush = @(varargin)flush(serialcon,varargin{:});    %Buffer flush functions.';
			'        vulintus_serial.read = ...';
			'            @(count,datatype)read(serialcon,count,datatype);                %Read data from the serialport object.';
			'        vulintus_serial.write = ...';
			'            @(data,datatype)write(serialcon,data,datatype);                 %Write data to the serialport object.';
			'';
			'    case ''serial''                                                           %Older, deprecated serial functions.';
			'        vulintus_serial.bytes_available = @serialcon.BytesAvailable;        %Number of bytes available.';
			'        vulintus_serial.flush = ...';
			'            @()Vulintus_Serial_Basic_Functions_Flush_Serial(serialcon);     %Buffer flush functions.';
			'        vulintus_serial.read = ...';
			'            @(count,datatype)fread(serialcon,count,datatype);               %Read data from the serialport object.';
			'        vulintus_serial.write = ...';
			'            @(data,datatype)fwrite(serialcon,data,datatype);                %Write data to the serialport object.';
			'';
			'end';
			'';
			'';
			'function Vulintus_Serial_Basic_Functions_Flush_Serial(serialcon)';
			'if serialcon.BytesAvailable                                                 %If there''s currently any data on the serial line.';
			'    fread(serialcon,serialcon.BytesAvailable);                              %Clear the input buffer.';
			'end';
		};

	case 'Vulintus_Return_Data_Type_Size'
		txt =	{
			'function n_bytes = Vulintus_Return_Data_Type_Size(data_type)';
			'';
			'%Vulintus_Return_Data_Type_Size.m - Vulintus, Inc., 2024';
			'%';
			'%   VULINTUS_RETURN_DATA_TYPE_SIZE returns the size, in bytes, of a single';
			'%   element of the classes specified by "data_type".';
			'%';
			'%   UPDATE LOG:';
			'%   2024-06-07 - Drew Sloan - Function first created.';
			'%';
			'';
			'switch lower(data_type)                                                     %Switch between the available data types...';
			'    case {''int8'',''uint8'',''char''}                                            %For 8-bit data types...';
			'        n_bytes = 1;                                                        %The number of bytes is the size of the request.';
			'    case {''int16'',''uint16''}                                                 %For 16-bit data types...';
			'        n_bytes = 2;                                                        %The number of bytes is the 2x size of the request.';
			'    case {''int32'',''uint32'',''single''}                                        %For 32-bit data types...';
			'        n_bytes = 4;                                                        %The number of bytes is the 4x size of the request. ';
			'    case {''uint64'',''double''}                                                %For 64-bit data types...';
			'        n_bytes = 8;                                                        %The number of bytes is the 8x size of the request.';
			'    otherwise                                                               %For any unrecognized classes.';
			'        error(''ERROR IN %s: Unrecognized variable class "%s"'',...';
			'            upper(mfilename),data_type);                                    %Show an error.';
			'end     ';
		};

	case 'cprintf'
		txt =	{
			'function count = cprintf(style,format,varargin)';
			'% CPRINTF displays styled formatted text in the Command Window';
			'%';
			'% Syntax:';
			'%    count = cprintf(style,format,...)';
			'%';
			'% Description:';
			'%    CPRINTF processes the specified text using the exact same FORMAT';
			'%    arguments accepted by the built-in SPRINTF and FPRINTF functions.';
			'%';
			'%    CPRINTF then displays the text in the Command Window using the';
			'%    specified STYLE argument. The accepted styles are those used for';
			'%    Matlab''s syntax highlighting (see: File / Preferences / Colors / ';
			'%    M-file Syntax Highlighting Colors), and also user-defined colors.';
			'%';
			'%    The possible pre-defined STYLE names are:';
			'%';
			'%       ''Text''                 - default: black';
			'%       ''Keywords''             - default: blue';
			'%       ''Comments''             - default: green';
			'%       ''Strings''              - default: purple';
			'%       ''UnterminatedStrings''  - default: dark red';
			'%       ''SystemCommands''       - default: orange';
			'%       ''Errors''               - default: light red';
			'%       ''Hyperlinks''           - default: underlined blue';
			'%';
			'%       ''Black'',''Cyan'',''Magenta'',''Blue'',''Green'',''Red'',''Yellow'',''White''';
			'%';
			'%    STYLE beginning with ''-'' or ''_'' will be underlined. For example:';
			'%          ''-Blue'' is underlined blue, like ''Hyperlinks'';';
			'%          ''_Comments'' is underlined green etc.';
			'%';
			'%    STYLE beginning with ''*'' will be bold (R2011b+ only). For example:';
			'%          ''*Blue'' is bold blue;';
			'%          ''*Comments'' is bold green etc.';
			'%    Note: Matlab does not currently support both bold and underline,';
			'%          only one of them can be used in a single cprintf command. But of';
			'%          course bold and underline can be mixed by using separate commands.';
			'%';
			'%    STYLE also accepts a regular Matlab RGB vector, that can be underlined';
			'%    and bolded: -[0,1,1] means underlined cyan, ''*[1,0,0]'' is bold red.';
			'%';
			'%    STYLE is case-insensitive and accepts unique partial strings just';
			'%    like handle property names.';
			'%';
			'%    CPRINTF by itself, without any input parameters, displays a demo';
			'%';
			'% Example:';
			'%    cprintf;   % displays the demo';
			'%    cprintf(''text'',   ''regular black text'');';
			'%    cprintf(''hyper'',  ''followed %s'',''by'');';
			'%    cprintf(''key'',    ''%d colored'', 4);';
			'%    cprintf(''-comment'',''& underlined'');';
			'%    cprintf(''err'',    ''elements\n'');';
			'%    cprintf(''cyan'',   ''cyan'');';
			'%    cprintf(''_green'', ''underlined green'');';
			'%    cprintf(-[1,0,1], ''underlined magenta'');';
			'%    cprintf([1,0.5,0],''and multi-\nline orange\n'');';
			'%    cprintf(''*blue'',  ''and *bold* (R2011b+ only)\n'');';
			'%    cprintf(''string'');  % same as fprintf(''string'') and cprintf(''text'',''string'')';
			'%';
			'% Bugs and suggestions:';
			'%    Please send to Yair Altman (altmany at gmail dot com)';
			'%';
			'% Warning:';
			'%    This code heavily relies on undocumented and unsupported Matlab';
			'%    functionality. It works on Matlab 7+, but use at your own risk!';
			'%';
			'%    A technical description of the implementation can be found at:';
			'%    <a href="http://undocumentedmatlab.com/blog/cprintf/">http://UndocumentedMatlab.com/blog/cprintf/</a>';
			'%';
			'% Limitations:';
			'%    1. In R2011a and earlier, a single space char is inserted at the';
			'%       beginning of each CPRINTF text segment (this is ok in R2011b+).';
			'%';
			'%    2. In R2011a and earlier, consecutive differently-colored multi-line';
			'%       CPRINTFs sometimes display incorrectly on the bottom line.';
			'%       As far as I could tell this is due to a Matlab bug. Examples:';
			'%         >> cprintf(''-str'',''under\nline''); cprintf(''err'',''red\n''); % hidden ''red'', unhidden ''_''';
			'%         >> cprintf(''str'',''regu\nlar''); cprintf(''err'',''red\n''); % underline red (not purple) ''lar''';
			'%';
			'%    3. Sometimes, non newline (''\n'')-terminated segments display unstyled';
			'%       (black) when the command prompt chevron (''>>'') regains focus on the';
			'%       continuation of that line (I can''t pinpoint when this happens). ';
			'%       To fix this, simply newline-terminate all command-prompt messages.';
			'%';
			'%    4. In R2011b and later, the above errors appear to be fixed. However,';
			'%       the last character of an underlined segment is not underlined for';
			'%       some unknown reason (add an extra space character to make it look better)';
			'%';
			'%    5. In old Matlab versions (e.g., Matlab 7.1 R14), multi-line styles';
			'%       only affect the first line. Single-line styles work as expected.';
			'%       R14 also appends a single space after underlined segments.';
			'%';
			'%    6. Bold style is only supported on R2011b+, and cannot also be underlined.';
			'%';
			'% Change log:';
			'%    2012-08-09: Graceful degradation support for deployed (compiled) and non-desktop applications; minor bug fixes';
			'%    2012-08-06: Fixes for R2012b; added bold style; accept RGB string (non-numeric) style';
			'%    2011-11-27: Fixes for R2011b';
			'%    2011-08-29: Fix by Danilo (FEX comment) for non-default text colors';
			'%    2011-03-04: Performance improvement';
			'%    2010-06-27: Fix for R2010a/b; fixed edge case reported by Sharron; CPRINTF with no args runs the demo';
			'%    2009-09-28: Fixed edge-case problem reported by Swagat K';
			'%    2009-05-28: corrected nargout behavior sugegsted by Andreas Gäb';
			'%    2009-05-13: First version posted on <a href="http://www.mathworks.com/matlabcentral/fileexchange/authors/27420">MathWorks File Exchange</a>';
			'%';
			'% See also:';
			'%    sprintf, fprintf';
			'';
			'% License to use and modify this code is granted freely to all interested, as long as the original author is';
			'% referenced and attributed as such. The original author maintains the right to be solely associated with this work.';
			'';
			'% Programmed and Copyright by Yair M. Altman: altmany(at)gmail.com';
			'% $Revision: 1.08 $  $Date: 2012/10/17 21:41:09 $';
			'';
			'  persistent majorVersion minorVersion';
			'  if isempty(majorVersion)';
			'      %v = version; if str2double(v(1:3)) <= 7.1';
			'      %majorVersion = str2double(regexprep(version,''^(\d+).*'',''$1''));';
			'      %minorVersion = str2double(regexprep(version,''^\d+\.(\d+).*'',''$1''));';
			'      %[a,b,c,d,versionIdStrs]=regexp(version,''^(\d+)\.(\d+).*'');  %#ok unused';
			'      v = sscanf(version, ''%d.'', 2);';
			'      majorVersion = v(1); %str2double(versionIdStrs{1}{1});';
			'      minorVersion = v(2); %str2double(versionIdStrs{1}{2});';
			'  end';
			'';
			'  % The following is for debug use only:';
			'  %global docElement txt el';
			'  if ~exist(''el'',''var'') || isempty(el),  el=handle([]);  end  %#ok mlint short-circuit error ("used before defined")';
			'  if nargin<1, showDemo(majorVersion,minorVersion); return;  end';
			'  if isempty(style),  return;  end';
			'  if all(ishandle(style)) && length(style)~=3';
			'      dumpElement(style);';
			'      return;';
			'  end';
			'';
			'  % Process the text string';
			'  if nargin<2, format = style; style=''text'';  end';
			'  %error(nargchk(2, inf, nargin, ''struct''));';
			'  %str = sprintf(format,varargin{:});';
			'';
			'  % In compiled mode';
			'  try useDesktop = usejava(''desktop''); catch, useDesktop = false; end';
			'  if isdeployed | ~useDesktop %#ok<OR2> - for Matlab 6 compatibility';
			'      % do not display any formatting - use simple fprintf()';
			'      % See: http://undocumentedmatlab.com/blog/bold-color-text-in-the-command-window/#comment-103035';
			'      % Also see: https://mail.google.com/mail/u/0/?ui=2&shva=1#all/1390a26e7ef4aa4d';
			'      % Also see: https://mail.google.com/mail/u/0/?ui=2&shva=1#all/13a6ed3223333b21';
			'      count1 = fprintf(format,varargin{:});';
			'  else';
			'      % Else (Matlab desktop mode)';
			'      % Get the normalized style name and underlining flag';
			'      [underlineFlag, boldFlag, style] = processStyleInfo(style);';
			'';
			'      % Set hyperlinking, if so requested';
			'      if underlineFlag';
			'          format = [''<a href="">'' format ''</a>''];';
			'';
			'          % Matlab 7.1 R14 (possibly a few newer versions as well?)';
			'          % have a bug in rendering consecutive hyperlinks';
			'          % This is fixed by appending a single non-linked space';
			'          if majorVersion < 7 || (majorVersion==7 && minorVersion <= 1)';
			'              format(end+1) = '' '';';
			'          end';
			'      end';
			'';
			'      % Set bold, if requested and supported (R2011b+)';
			'      if boldFlag';
			'          if (majorVersion > 7 || minorVersion >= 13)';
			'              format = [''<strong>'' format ''</strong>''];';
			'          else';
			'              boldFlag = 0;';
			'          end';
			'      end';
			'';
			'      % Get the current CW position';
			'      cmdWinDoc = com.mathworks.mde.cmdwin.CmdWinDocument.getInstance;';
			'      lastPos = cmdWinDoc.getLength;';
			'';
			'      % If not beginning of line';
			'      bolFlag = 0;  %#ok';
			'      %if docElement.getEndOffset - docElement.getStartOffset > 1';
			'          % Display a hyperlink element in order to force element separation';
			'          % (otherwise adjacent elements on the same line will be merged)';
			'          if majorVersion<7 || (majorVersion==7 && minorVersion<13)';
			'              if ~underlineFlag';
			'                  fprintf(''<a href=""> </a>'');  %fprintf(''<a href=""> </a>\b'');';
			'              elseif format(end)~=10  % if no newline at end';
			'                  fprintf('' '');  %fprintf('' \b'');';
			'              end';
			'          end';
			'          %drawnow;';
			'          bolFlag = 1;';
			'      %end';
			'';
			'      % Get a handle to the Command Window component';
			'      mde = com.mathworks.mde.desk.MLDesktop.getInstance;';
			'      cw = mde.getClient(''Command Window'');';
			'      xCmdWndView = cw.getComponent(0).getViewport.getComponent(0);';
			'';
			'      % Store the CW background color as a special color pref';
			'      % This way, if the CW bg color changes (via File/Preferences), ';
			'      % it will also affect existing rendered strs';
			'      com.mathworks.services.Prefs.setColorPref(''CW_BG_Color'',xCmdWndView.getBackground);';
			'';
			'      % Display the text in the Command Window';
			'      count1 = fprintf(2,format,varargin{:});';
			'';
			'      %awtinvoke(cmdWinDoc,''remove'',lastPos,1);   % TODO: find out how to remove the extra ''_''';
			'      drawnow;  % this is necessary for the following to work properly (refer to Evgeny Pr in FEX comment 16/1/2011)';
			'      docElement = cmdWinDoc.getParagraphElement(lastPos+1);';
			'      if majorVersion<7 || (majorVersion==7 && minorVersion<13)';
			'          if bolFlag && ~underlineFlag';
			'              % Set the leading hyperlink space character (''_'') to the bg color, effectively hiding it';
			'              % Note: old Matlab versions have a bug in hyperlinks that need to be accounted for...';
			'              %disp('' ''); dumpElement(docElement)';
			'              setElementStyle(docElement,''CW_BG_Color'',1+underlineFlag,majorVersion,minorVersion); %+getUrlsFix(docElement));';
			'              %disp('' ''); dumpElement(docElement)';
			'              el(end+1) = handle(docElement);  %#ok used in debug only';
			'          end';
			'';
			'          % Fix a problem with some hidden hyperlinks becoming unhidden...';
			'          fixHyperlink(docElement);';
			'          %dumpElement(docElement);';
			'      end';
			'';
			'      % Get the Document Element(s) corresponding to the latest fprintf operation';
			'      while docElement.getStartOffset < cmdWinDoc.getLength';
			'          % Set the element style according to the current style';
			'          %disp('' ''); dumpElement(docElement)';
			'          specialFlag = underlineFlag | boldFlag;';
			'          setElementStyle(docElement,style,specialFlag,majorVersion,minorVersion);';
			'          %disp('' ''); dumpElement(docElement)';
			'          docElement2 = cmdWinDoc.getParagraphElement(docElement.getEndOffset+1);';
			'          if isequal(docElement,docElement2),  break;  end';
			'          docElement = docElement2;';
			'          %disp('' ''); dumpElement(docElement)';
			'      end';
			'';
			'      % Force a Command-Window repaint';
			'      % Note: this is important in case the rendered str was not ''\n''-terminated';
			'      xCmdWndView.repaint;';
			'';
			'      % The following is for debug use only:';
			'      el(end+1) = handle(docElement);  %#ok used in debug only';
			'      %elementStart  = docElement.getStartOffset;';
			'      %elementLength = docElement.getEndOffset - elementStart;';
			'      %txt = cmdWinDoc.getText(elementStart,elementLength);';
			'  end';
			'';
			'  if nargout';
			'      count = count1;';
			'  end';
			'  return;  % debug breakpoint';
			'';
			'% Process the requested style information';
			'function [underlineFlag,boldFlag,style] = processStyleInfo(style)';
			'  underlineFlag = 0;';
			'  boldFlag = 0;';
			'';
			'  % First, strip out the underline/bold markers';
			'  if ischar(style)';
			'      % Styles containing ''-'' or ''_'' should be underlined (using a no-target hyperlink hack)';
			'      %if style(1)==''-''';
			'      underlineIdx = (style==''-'') | (style==''_'');';
			'      if any(underlineIdx)';
			'          underlineFlag = 1;';
			'          %style = style(2:end);';
			'          style = style(~underlineIdx);';
			'      end';
			'';
			'      % Check for bold style (only if not underlined)';
			'      boldIdx = (style==''*'');';
			'      if any(boldIdx)';
			'          boldFlag = 1;';
			'          style = style(~boldIdx);';
			'      end';
			'      if underlineFlag && boldFlag';
			'          warning(''YMA:cprintf:BoldUnderline'',''Matlab does not support both bold & underline'')';
			'      end';
			'';
			'      % Check if the remaining style sting is a numeric vector';
			'      %styleNum = str2num(style); %#ok<ST2NM>  % not good because style=''text'' is evaled!';
			'      %if ~isempty(styleNum)';
			'      if any(style=='' '' | style=='','' | style=='';'')';
			'          style = str2num(style); %#ok<ST2NM>';
			'      end';
			'  end';
			'';
			'  % Style = valid matlab RGB vector';
			'  if isnumeric(style) && length(style)==3 && all(style<=1) && all(abs(style)>=0)';
			'      if any(style<0)';
			'          underlineFlag = 1;';
			'          style = abs(style);';
			'      end';
			'      style = getColorStyle(style);';
			'';
			'  elseif ~ischar(style)';
			'      error(''YMA:cprintf:InvalidStyle'',''Invalid style - see help section for a list of valid style values'')';
			'';
			'  % Style name';
			'  else';
			'      % Try case-insensitive partial/full match with the accepted style names';
			'      validStyles = {''Text'',''Keywords'',''Comments'',''Strings'',''UnterminatedStrings'',''SystemCommands'',''Errors'', ...';
			'                     ''Black'',''Cyan'',''Magenta'',''Blue'',''Green'',''Red'',''Yellow'',''White'', ...';
			'                     ''Hyperlinks''};';
			'      matches = find(strncmpi(style,validStyles,length(style)));';
			'';
			'      % No match - error';
			'      if isempty(matches)';
			'          error(''YMA:cprintf:InvalidStyle'',''Invalid style - see help section for a list of valid style values'')';
			'';
			'      % Too many matches (ambiguous) - error';
			'      elseif length(matches) > 1';
			'          error(''YMA:cprintf:AmbigStyle'',''Ambiguous style name - supply extra characters for uniqueness'')';
			'';
			'      % Regular text';
			'      elseif matches == 1';
			'          style = ''ColorsText'';  % fixed by Danilo, 29/8/2011';
			'';
			'      % Highlight preference style name';
			'      elseif matches < 8';
			'          style = [''Colors_M_'' validStyles{matches}];';
			'';
			'      % Color name';
			'      elseif matches < length(validStyles)';
			'          colors = [0,0,0; 0,1,1; 1,0,1; 0,0,1; 0,1,0; 1,0,0; 1,1,0; 1,1,1];';
			'          requestedColor = colors(matches-7,:);';
			'          style = getColorStyle(requestedColor);';
			'';
			'      % Hyperlink';
			'      else';
			'          style = ''Colors_HTML_HTMLLinks'';  % CWLink';
			'          underlineFlag = 1;';
			'      end';
			'  end';
			'';
			'% Convert a Matlab RGB vector into a known style name (e.g., ''[255,37,0]'')';
			'function styleName = getColorStyle(rgb)';
			'  intColor = int32(rgb*255);';
			'  javaColor = java.awt.Color(intColor(1), intColor(2), intColor(3));';
			'  styleName = sprintf(''[%d,%d,%d]'',intColor);';
			'  com.mathworks.services.Prefs.setColorPref(styleName,javaColor);';
			'';
			'% Fix a bug in some Matlab versions, where the number of URL segments';
			'% is larger than the number of style segments in a doc element';
			'function delta = getUrlsFix(docElement)  %#ok currently unused';
			'  tokens = docElement.getAttribute(''SyntaxTokens'');';
			'  links  = docElement.getAttribute(''LinkStartTokens'');';
			'  if length(links) > length(tokens(1))';
			'      delta = length(links) > length(tokens(1));';
			'  else';
			'      delta = 0;';
			'  end';
			'';
			'% fprintf(2,str) causes all previous ''_''s in the line to become red - fix this';
			'function fixHyperlink(docElement)';
			'  try';
			'      tokens = docElement.getAttribute(''SyntaxTokens'');';
			'      urls   = docElement.getAttribute(''HtmlLink'');';
			'      urls   = urls(2);';
			'      links  = docElement.getAttribute(''LinkStartTokens'');';
			'      offsets = tokens(1);';
			'      styles  = tokens(2);';
			'      doc = docElement.getDocument;';
			'';
			'      % Loop over all segments in this docElement';
			'      for idx = 1 : length(offsets)-1';
			'          % If this is a hyperlink with no URL target and starts with '' '' and is collored as an error (red)...';
			'          if strcmp(styles(idx).char,''Colors_M_Errors'')';
			'              character = char(doc.getText(offsets(idx)+docElement.getStartOffset,1));';
			'              if strcmp(character,'' '')';
			'                  if isempty(urls(idx)) && links(idx)==0';
			'                      % Revert the style color to the CW background color (i.e., hide it!)';
			'                      styles(idx) = java.lang.String(''CW_BG_Color'');';
			'                  end';
			'              end';
			'          end';
			'      end';
			'  catch';
			'      % never mind...';
			'  end';
			'';
			'% Set an element to a particular style (color)';
			'function setElementStyle(docElement,style,specialFlag, majorVersion,minorVersion)';
			'  %global tokens links urls urlTargets  % for debug only';
			'  global oldStyles';
			'  if nargin<3,  specialFlag=0;  end';
			'  % Set the last Element token to the requested style:';
			'  % Colors:';
			'  tokens = docElement.getAttribute(''SyntaxTokens'');';
			'  try';
			'      styles = tokens(2);';
			'      oldStyles{end+1} = styles.cell;';
			'';
			'      % Correct edge case problem';
			'      extraInd = double(majorVersion>7 || (majorVersion==7 && minorVersion>=13));  % =0 for R2011a-, =1 for R2011b+';
			'      %{';
			'      if ~strcmp(''CWLink'',char(styles(end-hyperlinkFlag))) && ...';
			'          strcmp(''CWLink'',char(styles(end-hyperlinkFlag-1)))';
			'         extraInd = 0;%1;';
			'      end';
			'      hyperlinkFlag = ~isempty(strmatch(''CWLink'',tokens(2)));';
			'      hyperlinkFlag = 0 + any(cellfun(@(c)(~isempty(c)&&strcmp(c,''CWLink'')),tokens(2).cell));';
			'      %}';
			'';
			'      styles(end-extraInd) = java.lang.String('''');';
			'      styles(end-extraInd-specialFlag) = java.lang.String(style);  %#ok apparently unused but in reality used by Java';
			'      if extraInd';
			'          styles(end-specialFlag) = java.lang.String(style);';
			'      end';
			'';
			'      oldStyles{end} = [oldStyles{end} styles.cell];';
			'  catch';
			'      % never mind for now';
			'  end';
			'  ';
			'  % Underlines (hyperlinks):';
			'  %{';
			'  links = docElement.getAttribute(''LinkStartTokens'');';
			'  if isempty(links)';
			'      %docElement.addAttribute(''LinkStartTokens'',repmat(int32(-1),length(tokens(2)),1));';
			'  else';
			'      %TODO: remove hyperlink by setting the value to -1';
			'  end';
			'  %}';
			'';
			'  % Correct empty URLs to be un-hyperlinkable (only underlined)';
			'  urls = docElement.getAttribute(''HtmlLink'');';
			'  if ~isempty(urls)';
			'      urlTargets = urls(2);';
			'      for urlIdx = 1 : length(urlTargets)';
			'          try';
			'              if urlTargets(urlIdx).length < 1';
			'                  urlTargets(urlIdx) = [];  % '''' => []';
			'              end';
			'          catch';
			'              % never mind...';
			'              a=1;  %#ok used for debug breakpoint...';
			'          end';
			'      end';
			'  end';
			'  ';
			'  % Bold: (currently unused because we cannot modify this immutable int32 numeric array)';
			'  %{';
			'  try';
			'      %hasBold = docElement.isDefined(''BoldStartTokens'');';
			'      bolds = docElement.getAttribute(''BoldStartTokens'');';
			'      if ~isempty(bolds)';
			'          %docElement.addAttribute(''BoldStartTokens'',repmat(int32(1),length(bolds),1));';
			'      end';
			'  catch';
			'      % never mind - ignore...';
			'      a=1;  %#ok used for debug breakpoint...';
			'  end';
			'  %}';
			'  ';
			'  return;  % debug breakpoint';
			'';
			'% Display information about element(s)';
			'function dumpElement(docElements)';
			'  %return;';
			'  numElements = length(docElements);';
			'  cmdWinDoc = docElements(1).getDocument;';
			'  for elementIdx = 1 : numElements';
			'      if numElements > 1,  fprintf(''Element #%d:\n'',elementIdx);  end';
			'      docElement = docElements(elementIdx);';
			'      if ~isjava(docElement),  docElement = docElement.java;  end';
			'      %docElement.dump(java.lang.System.out,1)';
			'      disp('' '');';
			'      disp(docElement)';
			'      tokens = docElement.getAttribute(''SyntaxTokens'');';
			'      if isempty(tokens),  continue;  end';
			'      links = docElement.getAttribute(''LinkStartTokens'');';
			'      urls  = docElement.getAttribute(''HtmlLink'');';
			'      try bolds = docElement.getAttribute(''BoldStartTokens''); catch, bolds = []; end';
			'      txt = {};';
			'      tokenLengths = tokens(1);';
			'      for tokenIdx = 1 : length(tokenLengths)-1';
			'          tokenLength = diff(tokenLengths(tokenIdx+[0,1]));';
			'          if (tokenLength < 0)';
			'              tokenLength = docElement.getEndOffset - docElement.getStartOffset - tokenLengths(tokenIdx);';
			'          end';
			'          txt{tokenIdx} = cmdWinDoc.getText(docElement.getStartOffset+tokenLengths(tokenIdx),tokenLength).char;  %#ok';
			'      end';
			'      lastTokenStartOffset = docElement.getStartOffset + tokenLengths(end);';
			'      txt{end+1} = cmdWinDoc.getText(lastTokenStartOffset, docElement.getEndOffset-lastTokenStartOffset).char;  %#ok';
			'      %cmdWinDoc.uiinspect';
			'      %docElement.uiinspect';
			'      txt = strrep(txt'',sprintf(''\n''),''\n'');';
			'      try';
			'          data = [tokens(2).cell m2c(tokens(1)) m2c(links) m2c(urls(1)) cell(urls(2)) m2c(bolds) txt];';
			'          if elementIdx==1';
			'              disp(''    SyntaxTokens(2,1) - LinkStartTokens - HtmlLink(1,2) - BoldStartTokens - txt'');';
			'              disp(''    =============================================================================='');';
			'          end';
			'      catch';
			'          try';
			'              data = [tokens(2).cell m2c(tokens(1)) m2c(links) txt];';
			'          catch';
			'              disp([tokens(2).cell m2c(tokens(1)) txt]);';
			'              try';
			'                  data = [m2c(links) m2c(urls(1)) cell(urls(2))];';
			'              catch';
			'                  % Mtlab 7.1 only has urls(1)...';
			'                  data = [m2c(links) urls.cell];';
			'              end';
			'          end';
			'      end';
			'      disp(data)';
			'  end';
			'';
			'% Utility function to convert matrix => cell';
			'function cells = m2c(data)';
			'  %datasize = size(data);  cells = mat2cell(data,ones(1,datasize(1)),ones(1,datasize(2)));';
			'  cells = num2cell(data);';
			'';
			'% Display the help and demo';
			'function showDemo(majorVersion,minorVersion)';
			'  fprintf(''cprintf displays formatted text in the Command Window.\n\n'');';
			'  fprintf(''Syntax: count = cprintf(style,format,...);  click <a href="matlab:help cprintf">here</a> for details.\n\n'');';
			'  url = ''http://UndocumentedMatlab.com/blog/cprintf/'';';
			'  fprintf([''Technical description: <a href="'' url ''">'' url ''</a>\n\n'']);';
			'  fprintf(''Demo:\n\n'');';
			'  boldFlag = majorVersion>7 || (majorVersion==7 && minorVersion>=13);';
			'  s = [''cprintf(''''text'''',    ''''regular black text'''');'' 10 ...';
			'       ''cprintf(''''hyper'''',   ''''followed %s'''',''''by'''');'' 10 ...';
			'       ''cprintf(''''key'''',     ''''%d colored'''','' num2str(4+boldFlag) '');'' 10 ...';
			'       ''cprintf(''''-comment'''',''''& underlined'''');'' 10 ...';
			'       ''cprintf(''''err'''',     ''''elements:\n'''');'' 10 ...';
			'       ''cprintf(''''cyan'''',    ''''cyan'''');'' 10 ...';
			'       ''cprintf(''''_green'''',  ''''underlined green'''');'' 10 ...';
			'       ''cprintf(-[1,0,1],  ''''underlined magenta'''');'' 10 ...';
			'       ''cprintf([1,0.5,0], ''''and multi-\nline orange\n'''');'' 10];';
			'   if boldFlag';
			'       % In R2011b+ the internal bug that causes the need for an extra space';
			'       % is apparently fixed, so we must insert the sparator spaces manually...';
			'       % On the other hand, 2011b enables *bold* format';
			'       s = [s ''cprintf(''''*blue'''',   ''''and *bold* (R2011b+ only)\n'''');'' 10];';
			'       s = strrep(s, '''''')'','' '''')'');';
			'       s = strrep(s, '''''',5)'','' '''',5)'');';
			'       s = strrep(s, ''\n '',''\n'');';
			'   end';
			'   disp(s);';
			'   eval(s);';
			'';
			'';
			'%%%%%%%%%%%%%%%%%%%%%%%%%% TODO %%%%%%%%%%%%%%%%%%%%%%%%%';
			'% - Fix: Remove leading space char (hidden underline ''_'')';
			'% - Fix: Find workaround for multi-line quirks/limitations';
			'% - Fix: Non-\n-terminated segments are displayed as black';
			'% - Fix: Check whether the hyperlink fix for 7.1 is also needed on 7.2 etc.';
			'% - Enh: Add font support';
		};

end
