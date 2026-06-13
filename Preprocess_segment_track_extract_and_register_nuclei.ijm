/*  Macro to perform preprocessing, nuclei segmentation nuclei tracking (using StarDist and TrackMate),
 *  and image registration to stabilize the movement of individual nuclei.
 *  Under the hood it runs a few custom NKI scripts, for median background subtraction, starDist, Trackmate on the labelmap
 *  (implemented before TrackMate 7 was released), and extracting single nuclei tracks timelapse images.
 *  
 *  StarDist is performed on non-deconvolved raw images, because deconvolution tends to remove the nuclear background fluorescence
 *  that StarDist needs, in case there is no pan-nuclei marker channel. The deconvolved images are used for nuclei track extraction.
 *  
 *  The nuclei registration is performed with the plugin HyperStackReg (https://github.com/ved-sharma/HyperStackReg),
 *  using a rigid body transformation.
 *   
 *  Input: 2D+t timelapse images (raw and deconvolved max projections of 3D images; can also be twice the same) 
 *  Output:
 *  - Tracked full-image timelapse labelmaps
 *  - For each nucleus: single nuclei tracked images on a black background (extracted from the deconvolved images)
 *  - For each nucleus: single nuclei registered tracked images on a black background (extracted from the deconvolved images)
 *  
 *  https://github.com/BioImaging-NKI/Visualising-homology-search-in-human-cells
 * 
 *  Author: Bram van den Broek, Netherlands Cancer Institute
 *  @bramvdbroek at https://image.sc
 */

#@ File[] (label="Input files (max projections)", style="File") file_list
#@ File[] (label="Input corresponding deconvolved files", style="File") file_list_decon
#@ File (label="Output folder", style = "directory") output_folder
#@ Boolean (label="Extract only nuclei tracks already present in frame 1", value=true) only_first
#@ String (value="<html><br>Nuclei segmentation settings<hr></html>", visibility="MESSAGE") stardist_message
#@ Boolean (label="Subtract median background before StarDist?", value=false) subtract_background
#@ Boolean (label="Add all channels before StarDist", value=false) add_channels
#@ Integer (label="XY binning before StarDist", value=4, description="StarDist is trained on images with a certain pixel size.\nDownscaling high-resolution images may result in better segmentation.") stardist_scaling
#@ Double (label="Nuclei detection probability (lower=more nuclei)", min=0, max=1, value=0.5) stardist_probability
#@ Integer (label="Foci diameter", value=5, description="Foci are filtered out from the image before StarDist segmentation.") foci_diameter

debugMode=false;

stardist_scaling = 1/stardist_scaling;	//invert scaling factor
print("\\Clear");
if(only_first == true) print("Retrieving nuclei tracks only present in the first frame.");

if(!File.exists(output_folder)) File.makeDirectory(output_folder);

for (i = 0; i < file_list.length; i++) {
	run("Close All");

	open(file_list[i]);
	image_org = getTitle();
	run("Enhance Contrast", "saturated=0.35");
	getDimensions(width, height, channels, slices, frames);

	//Subtract background as the median of every pixel over time (this works only in case cells move a lot) 
	//To also include bleach correction, replace by:
	//if(subtract_background) run("NKI subtract median and bleach correct", "myImp="+image_org+", touint16=[false]");
	if(subtract_background) run("NKI subtract median", "myImp="+image_org+", touint16=[false]");

	//Segment nuclei using StarDist. Add channels together (currently unnormalized) for better accuracy
	if(add_channels && channels>1) {
		run("Re-order Hyperstack ...", "channels=[Slices (z)] slices=[Channels (c)] frames=[Frames (t)]");
		run("Z Project...", "projection=[Average Intensity] all");
	}
	image_for_StarDist = getTitle();
	run("Enhance Contrast", "saturated=0.35");
	outliers_radius = 3*foci_diameter;	//Empirically found that this works well
	
	//Intensity threshold 
//	outliers_threshold = percentile_value(image_for_StarDist, 0.99);	//Determine the 1% highest pixels. But should be subtracted by the mean nucleus value.
	outliers_threshold = 5;	//Or just use a hardcoded value
	
	run("NKI run stardist", "myImp="+image_for_StarDist+", channel=[2], scaling=["+stardist_scaling+"], min_label_size=[4000], max_label_size=[1000000], remove_outliers=[true], outliers_radius=["+outliers_radius+"], outliers_threshold=["+outliers_threshold+"], stardist_prob=["+stardist_probability+"]");
	rename("labelmap");
	labelmap_stardist = getTitle();
	run("glasbey_on_dark");
	setMinAndMax(0, 255);
	if(!debugMode) close("Label Image");
	if(!debugMode) close(image_for_StarDist);
	if(!debugMode) close(image_for_StarDist+"_scaled");

	run("NKI trackmate lblmap", "myImp="+labelmap_stardist+", allow_track_splitting=[false], gap_closing_max_distance=[200], linking_max_distance=[200], max_frame_gap=[3]");
	labelmap_tracked = getTitle();
	run("glasbey_on_dark");
	setMinAndMax(0, 255);
	
	if(!debugMode) close(labelmap_stardist);
	
	open(file_list_decon[i]);
	if(matches(file_list_decon[i], ".*cmle_ics.*")) run("Flip Vertically", "stack");	//Flip image back because Huygens messed it up
	image_decon = getTitle();

	output_folder_file = output_folder + File.separator + substring(image_decon, lastIndexOf(image_decon, ".ims")-2, lastIndexOf(image_decon, ".ims"));
	print("Saving extracted tracks into "+output_folder_file);
	if(!File.exists(output_folder_file)) File.makeDirectory(output_folder_file);

	selectWindow(labelmap_tracked);
	File.makeDirectory(output_folder_file + File.separator + "labelmap");
	saveAs("tif", output_folder_file + File.separator + "labelmap" + File.separator + "labelmap_tracked.tif");
	labelmap_tracked = getTitle();
	run("NKI extract tracks", "intensityimp=["+image_decon+"], labelimp=["+labelmap_tracked+"], only_first=[true], save_files=[true], make_composite=[false], to16bit=[false], output=["+output_folder_file+"]");

	run("CLIJ2 Macro Extensions", "cl_device=");
	Ext.CLIJ2_clear();
	register_tracks(output_folder_file, outliers_threshold);
}


// Register timelapse using HyperStackReg with Rigid body transformation
// We tested several registration algorithms (SIFT, Rigid Registration, etc.) but found good old HyperStackReg to be the most reliable.
function register_tracks(inputFolder, outliers_threshold) {
	tracklist = getFileList(inputFolder);
	tracklist = Array.sort(tracklist);
	for (i = 0; i < tracklist.length; i++) {
		if(endsWith(tracklist[i], ".tif") && !File.isDirectory(inputFolder + File.separator + tracklist[i])) {
			run("Close All");
			print("\\Update:Registering "+tracklist[i]);
			showProgress(tracklist[i], tracklist.length);	//assuming only .tif files present in the folder
			open(inputFolder + File.separator + tracklist[i]);
			image = getTitle();

			if(bitDepth()!=32) run("32-bit");
			getDimensions(width, height, channels, slices, frames);

			setBatchMode(true);
			//Possible pre-processing step. Remove /* and */ to include it
			/*
			mergeString = "";
			for (c = 1; c <= channels; c++) {
				correctedImage = subtractMeanOfPixelsAboveZero(image, c, outliers_threshold);
				mergeString += "c"+c+"="+correctedImage+" ";
			}
			run("Merge Channels...", mergeString+" create");
//			rename(image+"_adjusted");
			run("Re-order Hyperstack ...", "channels=[Channels (c)] slices=[Frames (t)] frames=[Slices (z)]");
			*/
			Stack.setChannel(2);
			run("Magenta");
			run("Enhance Contrast", "saturated=0.35");
			getMinAndMax(min, max);
			setMinAndMax(0, minOf(max, 20));
			Stack.setChannel(1);
			run("Green");
			run("Enhance Contrast", "saturated=0.35");
			getMinAndMax(min, max);
			setMinAndMax(0, minOf(max, 20));
			Stack.setDisplayMode("composite");
			saveAs("tif", inputFolder + File.separator + tracklist[i]);	

			setBatchMode(false);
			run("HyperStackReg ", "transformation=[Rigid Body] channel1 channel2");
			setBatchMode("show");
			rename(substring(image, 0, lastIndexOf(image, ".")) + "_registered");
			image_registered = getTitle();
			saveAs(inputFolder + File.separator + image_registered);

			//close(image);
			//close(image+"_adjusted");
			//close(image_registered);
		}
	}
}


function subtractMeanOfPixelsAboveZero(multiChannelImage, c, threshold) {
	selectWindow(multiChannelImage);
	run("Duplicate...", "title="+multiChannelImage+"_ch"+c+" duplicate channels="+c);
	image = multiChannelImage+"_ch"+c;
	Ext.CLIJ2_push(image);
	close(multiChannelImage+"_ch"+c);
	Ext.CLIJ2_meanOfPixelsAboveThreshold(image, threshold);
	meanAboveZero = getResult("Mean_of_pixels_above_threshold");
	meanAboveZero=0;	//Setting this back to zero, because it doesn't contribute much, and can lead to errors
	Ext.CLIJ2_addImageAndScalar(image, image_subtracted, -meanAboveZero);
	Ext.CLIJ2_replaceIntensity(image_subtracted, image_corrected, -meanAboveZero, 0);
	Ext.CLIJ2_pull(image_corrected);
	rename(image+"_corrected");
	Ext.CLIJ2_clear();
	return image+"_corrected";
}


//Find lower gray value of a (timelapse image at a certain percentile
function percentile_value(image, percentile) {
	selectWindow(image);
	getDimensions(width, height, channels, slices, frames);
	for (i = 0; i < frames; i++) {
		if(frames>1) Stack.setFrame(i+1);
		getRawStatistics(nPixels, mean, min, max, std, histogram);
		if(i > 0) histogram_all = addArrays(histogram_all, histogram);
		else histogram_all = Array.copy(histogram);
//		Array.print(histogram_all);
	}
	Stack.getStatistics(voxelCount, mean_stack, min_stack, max_stack, stdDev_stack);
	
	total = 0;
	bin=0;
	while (total < voxelCount*percentile) {
		total += histogram_all[bin];
		bin++;
	}
	return bin-1 - mean_stack;
}

//Adds two arrays of equal length element-wise
function addArrays(array1, array2) {
	added_array=newArray(maxOf(array1.length, array2.length));
	added_array = Array.copy(array1);
	for (a=0; a<minOf(array1.length, array2.length); a++) {
		added_array[a]=array1[a] + array2[a];
	}
	return added_array;
}
