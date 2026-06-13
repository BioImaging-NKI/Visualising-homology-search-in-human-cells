/*  This macro applies a Difference Of Gaussian filter, lets the user set a threshold,
 *  performs simple connected component analysis and displays the segmentations as overlay on the image.
 *  The user can decide to redo the threshold or continue. There's also a checkbox to batch segment
 *  the remaining images in the input file list.
 *   
 *  Input: image (2D/3D, no timelapse)
 *  Output: a labelmap with objects
 *  
 *  https://github.com/BioImaging-NKI/Visualising-homology-search-in-human-cells
 *  
 *  Author: Bram van den Broek, Netherlands Cancer Institute
 *  @bramvdbroek at https://image.sc
 */

#@ File[] (label = "Input image files", style = "file") inputFiles
#@ File (label = "Output directory", style = "directory") outputFolder
#@ Boolean (label = "Filter image before segmentation (sharpen features)?", value = true) runFilter
#@ Double (label = "Filter sigma (smaller = sharper)", value = 3.0, style="format:0.0") sigma
#@ Double (label = "autoscale: % saturated pixels", value = 0.1, style="format:0.00") saturatedPixels
#@ Integer (label = "Default threshold value", value = 2500) defaultThreshold
#@ Integer (label = "Minimum object size (voxels)", value = 50) minSize
blinkingTime = 500;

sigma1xy = 0.0;
sigma1z = 0.0;
sigma2xy = sigma;
sigma2z = sigma;
threshold = defaultThreshold;

setFont("SansSerif", 24, "antialiased");
setColor("Cyan");

setBatchMode(true);
print("\\Clear");

//Initialization
satisfied = "No";
useThresholdForAllImages = false;
redoThresholding = true;

for (i = 0; i < inputFiles.length; i++) {
	run("Close All");
	open(inputFiles[i]);
	print("Processing "+File.getName(inputFiles[i]));
	image = getTitle();
	getDimensions(width, height, channels, slices, frames);
	Stack.setSlice(floor(slices/2));
//	setMinAndMax(0, maxDisplayValue);
	run("Enhance Contrast", "saturated="+saturatedPixels);
	setBatchMode("show");

	run("CLIJ2 Macro Extensions", "cl_device=");
	Ext.CLIJ2_clear();
	Ext.CLIJ2_push(image);
	
	if(slices>1) {
		Ext.CLIJ2_extendedDepthOfFocusSobelProjection(image, image_focused, 10);
		Ext.CLIJ2_pull(image_focused);
		rename("Focused");
		run("Enhance Contrast", "saturated="+saturatedPixels);
	}
	run("Duplicate...", "title=Focused");
	selectWindow(image);
	if(runFilter) {
		Ext.CLIJ2_differenceOfGaussian3D(image, image_filtered, sigma1xy, sigma1xy, sigma1z, sigma2xy, sigma2xy, sigma2z);
		Ext.CLIJ2_pull(image_filtered);
		rename("Filtered");
		run("Enhance Contrast", "saturated="+saturatedPixels);
	}
	else {
		rename("Filtered");
		image_filtered = image;
	}
	if(slices>1) Stack.setSlice(floor(slices/2));
	run("Enhance Contrast", "saturated="+saturatedPixels);
	setBatchMode("show");

	while (satisfied == "No") {
		selectWindow("Filtered");
		run("Threshold...");
		resetThreshold();
		setThreshold(threshold, pow(2, 16)-1);
		if(useThresholdForAllImages == false) {
			waitForUser("Adjust threshold and press OK");
			getThreshold(threshold, upper);
		}
		resetThreshold();
		Ext.CLIJ2_threshold(image_filtered, image_thresholded, threshold);
		Ext.CLIJ2_connectedComponentsLabelingBox(image_thresholded, labelmap);
		Ext.CLIJ2_excludeLabelsOutsideSizeRange(labelmap, labelmap_filtered, minSize, 99999);
		Ext.CLIJ2_closeIndexGapsInLabelMap(labelmap_filtered, labelmap_filtered_gapsclosed);
		Ext.CLIJ2_pull(labelmap_filtered_gapsclosed);
		setBatchMode("hide");
		setMinAndMax(0, 255);
		run("glasbey_on_dark");
		rename("Objects");
		Stack.setSlice(floor(slices/2));
		setBatchMode("show");

		if(slices>1) run("Z Project...", "projection=[Max Intensity]");
		else run("Duplicate...", "title=MAX_Objects");
		setMinAndMax(0, 255);
		run("glasbey_on_dark");

		selectWindow("Focused");
		run("Add Image...", "image=MAX_Objects x=0 y=0 opacity=50 zero");
		setBatchMode("show");
		if(useThresholdForAllImages == false) {
			while(!isKeyDown("shift")) {
				Overlay.drawString("Inspect segmentation. Hold \"Shift\" to continue.", 100, 100);
				if (Overlay.size>0) {
					if (Overlay.hidden) Overlay.show;
					else Overlay.hide;
				}
				wait(blinkingTime);
			}
			Dialog.createNonBlocking("Are you satisfied with the segmentation?");
			Dialog.addRadioButtonGroup("Segmentation OK?", newArray("Yes", "No"), 1, 2, "Yes");
			Dialog.addMessage("Current threshold: "+threshold);
			Dialog.addCheckbox("Perform all other "+inputFiles.length-1-i+" images with this threshold", false);
			Dialog.show();
			satisfied = Dialog.getRadioButton();
			useThresholdForAllImages = Dialog.getCheckbox();
		}
		else satisfied = "Yes";

		if(satisfied == "No") {
			Overlay.remove();
			close("Objects");
			close("MAX_Objects");
			selectWindow("Focused");
			setBatchMode("hide");
		}
	}
	selectWindow("Objects");
	saveAs("Tiff", outputFolder + File.separator + File.getNameWithoutExtension(inputFiles[i]) + "_objects");
	print("threshold = "+threshold);
	satisfied = "No";
}
print("\nDone segmenting "+inputFiles.length+" images.");
Ext.CLIJ2_clear();
