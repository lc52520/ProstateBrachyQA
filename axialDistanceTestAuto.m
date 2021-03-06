function [result,knownVal,measuredVals,freq] = axialDistanceTestAuto(imageFile,varargin)
% AXIALDISTANCETESTAUTO is for the axial distance measurement accuracy quality control test.
% The function compares the axial distance measurement with the known
% value and checks if the error is larger than 2 mm (absolute) or 2% (relative). 

% Input parser
p = inputParser;
addRequired(p,'imageFile',@isnumeric);
addParameter(p,'UpperScale',[]);
addParameter(p,'LowerScale',[]);
addParameter(p,'AxesHandle',[]);
% Parse inputs
parse(p,imageFile,varargin{:});
upper = p.Results.UpperScale;
lower = p.Results.LowerScale;
axesHandle = p.Results.AxesHandle;

% If user has given the scale readings
if ~isempty(upper) && ~isempty(lower)
    % Get pixel scale using scale readings inputted by user
    pixelScale = getPixelScale(imageFile,upper,lower);
else
    % Get the pixel to mm conversion ratio, automatically reading scale
    % labels from the image
    pixelScale = getPixelScale(imageFile);
end

% Read frequency
freq = readFrequency(imageFile);

% Get baseline values
baselineFile = readBaselineFile('Baseline.xls');

% Get baseline value for this test
for i = 1:size(baselineFile,1)
    if ~isempty(strfind(baselineFile{i,1},'Axial distance'))
        knownVal = baselineFile{i,2};
    end
end

% Crop to ultrasound image
im_orig = imageFile;
width = size(im_orig,2);
height = size(im_orig,1);
% Crop dimensions
cropX = round(0.15*width);
cropY = round(0.2*height);
cropWidth = round(0.7*width);
cropHeight = round(0.65*height);
im_cropped = im_orig(cropY:cropY+cropHeight,cropX:cropX+cropWidth);
% Make all non-black objects white
im_bw = im2bw(im_cropped,0.01);
% Get indices of rows/columns with nonzero elements
[row col] = find(im_bw);
% Crop tight to objects
im_tight = im_cropped(min(row):max(row),min(col):max(col));

% Store x and y offset for positioning cropped image relative to original image. 
xOffset = cropX + min(col) - 2;
yOffset = cropY + min(row) - 2;

% Use bottom-hat filter to make bright filaments black
botfilt = imbothat(im_tight,strel('disk',20));
% Blur image to help reduce background noise
medfilt = medfilt2(botfilt,[1,5]);
% Convert to binary image where filaments are black
bw = im2bw(medfilt,0);
% Invert image so filaments are white on black background
bw = imcomplement(bw);

% Remove unwanted white areas from edges of image (scale tick markings, top
% and bottom of ultrasound image)
bw(:,1:70) = 0;         % Remove left edge
bw(:,end-70:end) = 0;   % Remove right edge
bw(1:120,:) = 0;         % Remove top edge
bw(end-120:end,:) = 0;   % Remove bottom edge

% Remove large objects
bw = bw - bwareaopen(bw,300);
% Remove small objects
bw = bwareaopen(bw,20);

% Get the filament region properties
bwRegions = regionprops(bw,'Centroid','MajorAxisLength','MinorAxisLength','Area','Orientation');

% Only keep regions with expected major and minor axis length
majorAxisLength = [bwRegions.MajorAxisLength]';
majorAxisInd = find(majorAxisLength>8 & majorAxisLength<60);
minorAxisLength = [bwRegions.MinorAxisLength]';
minorAxisInd = find(minorAxisLength>2.5);
filaments = intersect(majorAxisInd,minorAxisInd);
bw = ismember(bwlabel(bw),filaments);
% Get the filament region properties
regions = regionprops(bw,'Centroid','MajorAxisLength','MinorAxisLength','Area','Orientation');

% Check for false detections by checking that mean intensity inside region
% is greater than surrounding area
filaments = [];
for r = 1:numel(regions)
    insideMask = ismember(bwlabel(bw),r);
    insideReg = im_tight.*uint8(insideMask);
    outsideMask = imdilate(insideMask,strel('disk',30)) - insideMask;
    outsideReg = im_tight.*uint8(outsideMask);
    meanInside = mean(insideReg(insideReg>0));
    meanOutside = mean(outsideReg(outsideReg>0));
    if meanInside/meanOutside > 1.4
        filaments = [filaments; r];
    end
end
bw = ismember(bwlabel(bw),filaments);
% Get the updated filament region properties
regions = regionprops(bw,'Centroid','MajorAxisLength','MinorAxisLength','Area','Orientation');

% Only use the brightest 40% of each region
for r = 1:numel(regions)
    regBW = ismember(bwlabel(bw),r);
    reg = im_tight.*uint8(regBW);
    maxBright = max(reg(:));
    % Remove pixels less than local brightness threshold
    reg(reg<0.6*maxBright) = 0;
    % Keep largest region
    reg = im2bw(reg,0);
    props = regionprops(reg,'Area');
    [~,largest] = max([props.Area]);
    reg = ismember(bwlabel(reg),largest);
    newReg(:,:,r) = reg;
end
bw = im2bw(sum(newReg,3));
% Get the updated filament region properties
regions = regionprops(bw,'Centroid','MajorAxisLength','MinorAxisLength','Area','Orientation');

% Get centroids of filament regions
for n = 1:numel(regions)
    centroids(n,:) = regions(n).Centroid;
end

% -------------------------------------------------------------------------
% Get the indices of the corner filaments
% Top left
topLeftCorner = [0 0];
% Get distances from corner to centroids
vectors = centroids - repmat(topLeftCorner,size(centroids,1),1);
distances = sqrt(vectors(:,1).^2 + vectors(:,2).^2);
[topLeftDist,topLeftInd] = min(distances);

% Top right
topRightCorner = [size(bw,2) 0];
% Get distances from corner to centroids
vectors = centroids - repmat(topRightCorner,size(centroids,1),1);
distances = sqrt(vectors(:,1).^2 + vectors(:,2).^2);
[topRightDist,topRightInd] = min(distances);

% Bottom left
bottomLeftCorner = [0 size(bw,1)];
% Get distances from corner to centroids
vectors = centroids - repmat(bottomLeftCorner,size(centroids,1),1);
distances = sqrt(vectors(:,1).^2 + vectors(:,2).^2);
[bottomLeftDist,bottomLeftInd] = min(distances);

% Top right
bottomRightCorner = [size(bw,2) size(bw,1)];
% Get distances from corner to centroids
vectors = centroids - repmat(bottomRightCorner,size(centroids,1),1);
distances = sqrt(vectors(:,1).^2 + vectors(:,2).^2);
[bottomRightDist,bottomRightInd] = min(distances);

% Check orientation by using position of 6th filament (left of center)
dist_topLeft = norm(regions(topLeftInd).Centroid - regions(6).Centroid);
dist_bottomLeft = norm(regions(bottomLeftInd).Centroid - regions(6).Centroid);
if dist_bottomLeft < dist_topLeft
    % bottomleft = B1, bottomright = F1, topleft = B5, topright = F5
    filamentIndices = [topLeftInd,bottomLeftInd,topRightInd,bottomRightInd];
else
    % bottomleft = F1, bottomright = B1, topleft = F5, topright = B5
    filamentIndices = [topRightInd,bottomRightInd,topLeftInd,bottomLeftInd];
end
% -------------------------------------------------------------------------

% Loop through corner filaments
points = [];
for f = filamentIndices
    % Centroid of filament
    centroid = regions(f).Centroid;
    % Angle between x-axis and major axis of region (neg. because MATLAB y
    % increases going down)
    theta = -(regions(f).Orientation);
    % Length of major axis
    majorAxisLength = regions(f).MajorAxisLength;
    % Rotation matrix to get vector pointing along major axis
    R = [cosd(theta) -sind(theta); sind(theta) cosd(theta)];
    % Vector pointing along major axis
    v = R*[1;0];
    
    % Point on right side of filament for showing axial distance
    points = [points; centroid + (majorAxisLength/2)*v'];
end

% -------------------------------------------------------------------------
% Plot markers on figure to show points that were found
% Create column vectors for offsets, used for plotting markers
yOffset = repmat(yOffset,size(points,1),1);
xOffset = repmat(xOffset,size(points,1),1);

if ~isempty(axesHandle)
    % Plot on specified axes if given as input
    parent = axesHandle;
else
    % Otherwise, plot on new figure
    figure;
    parent = gca;
end

% Clear axes first
cla(parent);
% Plot image on axes
im = imshow(im_orig,'Parent',parent);
% Hold on
set(parent,'NextPlot','add');

% Get marker points corrected with x and y offset
markers = [xOffset+points(:,1),yOffset+points(:,2)];
% Plot axial distance lines
line1 = line(markers(1:2,1),markers(1:2,2),'LineStyle',':','Color','w','Parent',parent);
m1 = plot(markers(1:2,1),markers(1:2,2),...
    '+','MarkerSize',10,'Linewidth',1.5,'Color','r','Parent',parent);
if size(markers,1)>2
    line2 = line(markers(3:4,1),markers(3:4,2),'LineStyle',':','Color','w','Parent',parent);
    m2 = plot(markers(3:4,1),markers(3:4,2),...
        '+','MarkerSize',10,'Linewidth',1.5,'Color','g','Parent',parent);
end

% -------------------------------------------------------------------------

% Left side axial distance
axialDist1_pixels = norm(markers(2,:)-markers(1,:));
axialDist1_mm = axialDist1_pixels*pixelScale;
measuredVals = axialDist1_mm;
% Right side axial distance
if size(markers,1)>2
    axialDist2_pixels = norm(markers(4,:)-markers(3,:));
    axialDist2_mm = axialDist2_pixels*pixelScale;
    measuredVals = [measuredVals axialDist2_mm];
end

% Figure title
% title(['Axial distance = ' sprintf('%.2f',newVal) ' mm']);
% Legend
if exist('m2','var')
    l = legend([m1,m2],['Dist: ' sprintf('%.2f',axialDist1_mm) ' mm'],...
        ['Dist: ' sprintf('%.2f',axialDist2_mm) ' mm'],...
        'Location','southeast','Orientation','horizontal');
else
    l = legend(m1,['Dist: ' sprintf('%.2f',axialDist1_mm) ' mm'],...
        'Location','southeast','Orientation','horizontal');
end
% Change legend text and background colour
set(l,'TextColor','w','Color',[0.2 0.2 0.2]);

% Callback when double clicking on image
set(im,'ButtonDownFcn',@(obj,eventdata)showInFigure(parent,l));

disp(['Known value: ' sprintf('%.2f',knownVal) ' mm']);

if numel(measuredVals) > 1
    disp(' ');
    disp('Measured values:');
    disp(['Left: ' sprintf('%.2f',measuredVals(1)) ' mm']);
    disp(['Right: ' sprintf('%.2f',measuredVals(2)) ' mm']);
    disp(' ');
else
    disp(['Measured value: ' sprintf('%.2f',measuredVals)]);
end

error = abs(measuredVals-repmat(knownVal,size(measuredVals)));
% Check measured axial distance measurement errors
if isnan(error)
    result = [];
else
    result = error<=2 | error<=0.02*knownVal;
end
if isempty(result)
    disp('Missing information - could not complete test');
elseif any(result == 0)
    % Fail
    disp('Axial distance measurement accuracy test: failed');
else
    % Pass
    disp('Axial distance measurement accuracy test: passed');
end

end