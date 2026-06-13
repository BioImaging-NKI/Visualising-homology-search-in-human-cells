/*  Macro to segment foci/structures in the nucleus using LabKit.
 *  It runs an existing LabKit classifier, extracts the segmented label nr. 1
 *  and merges channels with the selected channel of the original image (in grays).
 *  
 *  Input: 2D/3D/4D images and a suitable labkit classifier file
 *  Output: 2-channel merged images of the original selected segmentation channel and the segmentation masks  
 *  
 *  https://github.com/BioImaging-NKI/Visualising-homology-search-in-human-cells
 *  
 *  Author: Bram van den Broek, Netherlands Cancer Institute
 *  @bramvdbroek at https://image.sc
 */

#@ File[]	inputFiles			(label = "Input images", style="File")
#@ File		outputFolder		(label = "Output folder", style="Directory")
#@ File		labkitClassifierFile(label = "Labkit classifier file", style="File")
#@ Boolean 	useGPU				(label = "Use GPU (Labkit)", value=true)
#@ Integer 	medianRadius		(label = "Smooth segmentation masks with median radius", value=1, min=0)
#@ Integer 	SegmentationChannel	(label = "Segmentation channel", value=1, min=0)

//setBatchMode(true);
print("\\Clear");
for (i=0; i<inputFiles.length; i++) {
	run("Close All");
	open(inputFiles[i]);
	image = getTitle();
	getDimensions(width, height, channels, slices, frames);
	print("Segmenting and merging image "+i+1+"/"+inputFiles.length+" : "+image);

	run("Segment Image With Labkit", "minimum=0 maximum=2 unsigned=Automatic input=["+image+"] segmenter_file=["+labkitClassifierFile+"] use_gpu="+useGPU);
	rename("segmentation");
	for (t = 1; t <= frames; t++) {
		setSlice(t);
		changeValues(2, 99, 0);	//Set all segmentations except label 1 to zero. Change/add lines if you need another label nr.
	}
	setSlice(1);
	setThreshold(1, 255);
	run("Convert to Mask", "background=Dark black");
	run("Median", "radius="+medianRadius+" stack");
	run("32-bit");
	run("Divide...", "value=2.000 stack");
	rename("mask");
	close("segmentation");
	selectImage(image);
	run("Duplicate...", "duplicate channels="+SegmentationChannel);
	rename("RAD51");
	
	run("Merge Channels...", "c1=RAD51 c2=mask create");
	Stack.setChannel(2);
	run("Red");
	setMinAndMax(0, 255);
	Stack.setChannel(1);
	run("Grays");
	setMinAndMax(90, 154);
	
	saveAs("tiff", outputFolder + File.separator + File.getNameWithoutExtension(inputFiles[i]) + "_merged.tif");
}
print("\nDone!");