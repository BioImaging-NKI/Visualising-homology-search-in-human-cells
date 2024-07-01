#@ File[] (label = "Input files", style="File") inputFiles
#@ Boolean (label = "Also process the object maps", value = true, description = "The next field is ignored when unchecked, but it cannot be empty.") saveCrops
#@ File[] (label = "Corresponding object map files", style="File", description = "Cannot be left empty, but is ignored when previous checkbox is unchecked") inputObjectMapFiles
#@ File (label = "Output folder", style="Directory") outputFolder

#@ Integer (label = "Channel to save (-1 to keep all channels)", value = 1, min = -1, ) saveChannel
#@ Integer (label = "Nuclei channel", value = 4, min = 1, ) nucleiChannel
#@ Integer (label = "Pre-StarDist image downscale factor (-1 for automatic)", value = -1, min = -1, description="The macro uses StarDist's pre-trained deep learning model for nuclei prediction. The network is not trained on high-resolution images; downscaling helps to correctly identify the nuclei.") downsampleFactorSetting
#@ Double (label = "Nuclei probability threshold [0-1]", value = 0.5, min = 0, max = 1, style = "slider", stepsize=0.05, description="Higher values accept less nuclei") probabilityThreshold

#@ Integer (label = "Remove nulei/cells with diameter smaller than (um)", value = 4, min = 0) minNucleusSize_setting
#@ Double (label = "Grow segmented nuclei with (um)", value = 0.5,  style="format:0.0") growSize_setting
#@ Boolean (label = "Exclude nuclei on image edges", value = false) excludeEdges
#@ Boolean (label = "Save crops of individual nuclei", value = true) saveCrops

saveImages = true;
maxNucleusSize_setting = 100;

outputFolder = outputFolder + File.separator;
outputImageFolder = outputFolder + "Images" + File.separator;
if(!File.exists(outputImageFolder)) File.makeDirectory(outputImageFolder);
outputImageFolderSingleNuclei = outputImageFolder + File.separator + "Single_Nuclei" + File.separator;
if(!File.exists(outputImageFolderSingleNuclei)) File.makeDirectory(outputImageFolderSingleNuclei);
if(inputObjectMapFiles.length > 0) {
	outputObjectMapFolder = outputFolder + "ObjectMaps" + File.separator;
	if(!File.exists(outputObjectMapFolder)) File.makeDirectory(outputObjectMapFolder);
	outputObjectMapFolderSingleNuclei = outputObjectMapFolder + File.separator + "Single_Nuclei" + File.separator;
	if(!File.exists(outputObjectMapFolderSingleNuclei)) File.makeDirectory(outputObjectMapFolderSingleNuclei);
}

setBatchMode(true);

run("CLIJ2 Macro Extensions", "cl_device=");
Ext.CLIJ2_clear();
// In case another GPU needs to be selected:
//Ext.CLIJ2_listAvailableGPUs();
//availableGPUs = Table.getColumn("GPUName");
//run("CLIJ2 Macro Extensions", "cl_device=" + availableGPUs[1]);

run("Close All");
run("Clear Results");
print("\\Clear");

for(f=0; f<inputFiles.length; f++) {
	//open(inputFiles[f]);
	run("Bio-Formats Importer", "open=["+inputFiles[f]+"] color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT");
	image = getTitle();
	imageName = File.getNameWithoutExtension(inputFiles[f]);
	getPixelSize(unit, pw, ph);
	
	if(downsampleFactorSetting == -1) {
		downsampleFactor = round(0.4/pw);
		//print("Automatic downscale factor: "+round(downsampleFactor));
	}
	else downsampleFactor = downsampleFactorSetting;
	
	growSize = growSize_setting / pw;
	minNucleusSize = PI*pow((minNucleusSize_setting / pw / 2),2);	//Calculate the nucleus area as if it were a circle
	maxNucleusSize = PI*pow((maxNucleusSize_setting / pw / 2),2);

	showProgress(f, inputFiles.length);
	showStatus("Processing image "+imageName+" ("+f+1+"/"+inputFiles.length+")");

	detect_nuclei(image, nucleiChannel, downsampleFactor);
	labelmap_nuclei_GPU = getLabelmap_GPU(image);

	Ext.CLIJ2_threshold(labelmap_nuclei_GPU, mask_nuclei, 1);		//Create binary
	Ext.CLIJ2_pull(mask_nuclei);
	rename("mask");
	Ext.CLIJ2_clear();

	selectWindow(image);
	if(saveChannel > 0) {
		run("Duplicate...", "duplicate channels="+saveChannel);
		close(image);
		rename(image);
	}

	imageCalculator("Multiply stack", image, "mask");
	if(inputObjectMapFiles.length > 0) {
		open(inputObjectMapFiles[f]);
		objectMap = getTitle();
		objectMapName = File.getNameWithoutExtension(inputObjectMapFiles[f]);
		imageCalculator("Multiply stack", objectMap, "mask");
	}
	
	if(saveCrops == true) {
		for (i = 0; i < roiManager("count"); i++) {
			selectWindow(image);
			roiManager("select", i);
			run("Enlarge...", "enlarge="+growSize+" pixel");
			run("Duplicate...", "duplicate");
			saveAs("tif", outputImageFolderSingleNuclei + imageName + "__nucleus"+i+1);
			close();
			if(inputObjectMapFiles.length > 0) {
				selectWindow(objectMap);
				roiManager("select", i);
				run("Enlarge...", "enlarge="+growSize+" pixel");
				run("Duplicate...", "duplicate");
				saveAs("tif", outputObjectMapFolderSingleNuclei + imageName + "__nucleus"+i+1+"_objectMap");
				close();
			}
		}
		roiManager("deselect");
	}

	if(saveImages == true) {
		selectWindow(image);
		roiManager("deselect");
		roiManager("Show all with labels");
		saveAs("tif", outputImageFolder + imageName + "__cleanedUp");
		roiManager("Show None");
		Overlay.remove;
		run("Z Project...", "projection=[Max Intensity]");
		rename("MAX_image");
		if(inputObjectMapFiles.length > 0) {
			selectWindow(objectMap);
			roiManager("deselect");
			roiManager("Show all with labels");
			saveAs("tif", outputObjectMapFolder + objectMapName + "__cleanedUp");

			run("Z Project...", "projection=[Max Intensity]");
			rename("MAX_objectMap");
			run("glasbey_on_dark");
			setMinAndMax(0, 255);

			selectWindow("MAX_image");
			roiManager("Show All without labels");
			
			run("Add Image...", "image=[MAX_objectMap] x=0 y=0 opacity=33 zero");
			saveAs("tif", outputFolder + imageName + "__MAX_overlay");
		}
	}
	run("Close All");
	roiManager("reset");
}


function detect_nuclei(image, channel, downsampleFactor) {
	selectWindow(image);
	getDimensions(width, height, channels, slices, frames);
	if(channels > 1) run("Duplicate...", "title=nuclei_stack duplicate channels="+channel);
	if(slices>1) {
		rename("nuclei_stack");
		run("Z Project...", "projection=[Max Intensity]");
		rename("nuclei");
		close("nuclei_stack");
	}
	if(downsampleFactor > 1) {
		run("Duplicate...", "duplicate title=nuclei_downscaled");
		run("Bin...", "x="+downsampleFactor+" y="+downsampleFactor+" bin=Average");
	}
	getDimensions(width, height, channels, slices, frames);

	starDistTiles = 1;
	// Run StarDist and output to the ROI manager (creating a label image works only when not operating in batch mode, and that is slower and more annoying Besides, this allows for easy ROI interpolation.)
	run("Command From Macro", "command=[de.csbdresden.stardist.StarDist2D], args=['input':'nuclei_downscaled', 'modelChoice':'Versatile (fluorescent nuclei)', 'normalizeInput':'true', 'percentileBottom':'1.0', 'percentileTop':'99.60000000000001', 'probThresh':'"+probabilityThreshold+"', 'nmsThresh':'0.3', 'outputType':'ROI Manager', 'nTiles':'"+starDistTiles+"', 'excludeBoundary':'2', 'roiPosition':'Stack', 'verbose':'false', 'showCsbdeepProgress':'false', 'showProbAndDist':'false'], process=[false]");

	//Scale up again
	if(downsampleFactor > 1) {
		showStatus("Scaling ROIs...");
		for(i=0;i<roiManager("count");i++) {
			if(i%100==0) showProgress(i/roiManager("count"));
			roiManager("Select",i);
			run("Scale... ", "x="+downsampleFactor+" y="+downsampleFactor);
			Roi.getSplineAnchors(x, y)
			Roi.setPolygonSplineAnchors(x, y);		//upscale ROIS with spline interpolation
			roiManager("update");
		}
	}
	close("nuclei");
	close("nuclei_downscaled");
}


function getLabelmap_GPU(image) {
	//Create labelmap
	run("ROI Manager to LabelMap(2D)");
	run("glasbey_on_dark");
	rename("labelmap");
	labelmap_nuclei_raw = getTitle();
	Ext.CLIJ2_push(labelmap_nuclei_raw);
	close("labelmap");
	
	//exclude labels on edges
	if(excludeEdges) Ext.CLIJ2_excludeLabelsOnEdges(labelmap_nuclei_raw, labelmap_nuclei);
	else labelmap_nuclei = labelmap_nuclei_raw;

	//Filter on area
	Ext.CLIJ2_getMaximumOfAllPixels(labelmap_nuclei, nucleiStarDist);	//count nuclei detected by StarDist
	run("Clear Results");
	Ext.CLIJ2_statisticsOfBackgroundAndLabelledPixels(labelmap_nuclei, labelmap_nuclei); //Somehow if you put (image, labelmap) as arguments the pixel count is wrong
	Ext.CLIJ2_pushResultsTableColumn(area, "PIXEL_COUNT");

	Ext.CLIJ2_excludeLabelsWithValuesOutOfRange(area, labelmap_nuclei, labelmap_nuclei_filtered, minNucleusSize, maxNucleusSize);
	Ext.CLIJ2_release(labelmap_nuclei);

	//Shrink nuclei/cells
	if(growSize < 0) {
		Ext.CLIJ2_erodeLabels(labelmap_nuclei_filtered, labelmap_final, growSize, false);
		Ext.CLIJ2_release(labelmap_nuclei_filtered);
	}
	else if(growSize > 0) {
		Ext.CLIJ2_dilateLabels(labelmap_nuclei_filtered, labelmap_final, growSize);
		Ext.CLIJ2_release(labelmap_nuclei_filtered);
	}
	else if(growSize == 0) labelmap_final = labelmap_nuclei_filtered;
	
	Ext.CLIJ2_getMaximumOfAllPixels(labelmap_final, nrNuclei);	//get the number of nuclei after filtering
	run("Clear Results");
	Ext.CLIJ2_closeIndexGapsInLabelMap(labelmap_final, labelmap_final_ordered);	//Renumber the cells from top to bottom
	Ext.CLIJ2_release(labelmap_final);
	Ext.CLIJ2_statisticsOfLabelledPixels(labelmap_final_ordered, labelmap_final_ordered); //Somehow if you put (image, labelmap) as arguments the pixel count is wrong
	print(image + " : " +nucleiStarDist+" nuclei detected by StarDist ; "+nucleiStarDist - nrNuclei+" nuclei with diameter outside ["+d2s(minNucleusSize_setting,0)+" - "+d2s(maxNucleusSize_setting,0)+"] "+unit+" range were removed ("+minNucleusSize+" - "+maxNucleusSize+" pixels).");

	return labelmap_final_ordered;
}
