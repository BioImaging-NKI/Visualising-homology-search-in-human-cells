/*  Macro to skeletonize labelmaps with structures in 2D or 3D,
 *  and measure length and shape features using CLIJ and MorphoLibJ.
 *   
 *  Due to the width of the structures the skeletons do not stretch all the way to the ends.
 *  Roundich structures sometimes ends up with a very small skeleton length, even a single pixel.
 *  The output 'Totallength' tries to compensate for this:
 *  - For every endpoint the distance to the edge of the label is added to the skeleton length.
 *  - For structures with only 1 endpoint (~circles/spheres), this distance is added twice.
 *   
 *  Input: a labelmap with objects (2D/3D)
 *  Output: Results table, saved as .tsv file
 *  
 *  https://github.com/BioImaging-NKI/Visualising-homology-search-in-human-cells
 *  
 *  Author: Bram van den Broek, Netherlands Cancer Institute
 *  @bramvdbroek at https://image.sc
 */

#@ File[] 	inputFiles		(label = "Input files (single nuclei object maps)", style = "file") 
#@ File		outputFolder	(label = "Output folder", style = "directory")
#@ Boolean	analyzeIn2D		(label = "Analyze in 2D", value=false)

remap = true;
endpoint_dilation_radius = 1;
isotropify = false;
//Correct for anisotropy? Meh, doesn't work well, and gives artifacts. Better keep as is.

run("CLIJ2 Macro Extensions", "cl_device=");
Ext.CLIJ2_clear();
print("\\Clear");

setBatchMode(true);

for (f=0; f<inputFiles.length; f++) {
	Ext.CLIJ2_clear();
	run("Close All");
	run("Clear Results");
	
	open(inputFiles[f]);
	labelmap = getTitle();
	if(selectionType() != -1) run("Clear Outside", "stack");
	getDimensions(width, height, channels, slices, frames);
	if(analyzeIn2D) {
		run("Z Project...", "projection=[Max Intensity]");
		run("glasbey_on_dark");
		setMinAndMax(0, 255);
		labelmap = getTitle();
	}
	else Stack.setSlice(round(slices/2));
	setBatchMode("show");

	print("Processing file "+f+1+"/"+inputFiles.length+"  |  "+labelmap);

	if(remap) run("Remap Labels");
	setMinAndMax(0, 255);

	if(analyzeIn2D) run("Analyze Regions", "area circularity convexity max._feret_diameter geodesic_diameter");
	else run("Analyze Regions 3D", "volume sphericity geodesic_diameter surface_area_method=[Crofton (13 dirs.)] euler_connectivity=26");
	resultsTable = getInfo("window.title");
	
	selectImage(labelmap);
	run("Duplicate...", "title=skeleton duplicate");
	run("8-bit");
	run("Skeletonize (2D/3D)");
	run("Grays");
	
	//isotropify = true;
	//if(isotropify) {
	//	selectImage("skeleton");
	//	setVoxelSize(0.35, 0.35, 1.5, "um");
	//	getDimensions(width, height, channels, slices, frames);
	//	getVoxelSize(pw, ph, pd, unit);
	//	run("Scale...", "x=1.0 y=1.0 z="+pd/pw+" interpolation=None process create");
	//	run("Properties...", "pixel_width="+pw+" pixel_height="+pw+" voxel_depth="+pw);	//make sure the numbers are exactly the same, otherwise MorphoLibJ crashes
	//	close("skeleton_iso");
	//	skeleton_iso = "skeleton_iso";
	//	rename(skeleton_iso);
	//	Ext.CLIJ2_push(skeleton_iso);
	//	Ext.CLIJ2_dilateSphere(skeleton_iso, skeleton_iso_dilated);
	//	Ext.CLIJ2_pull(skeleton_iso_dilated);
	//	run("Median 3D...", "x=2 y=2 z=2");
	//	setMinAndMax(0, 1);
	//	run("Skeletonize (2D/3D)");
	//	//NEED ALSO TO DO THIS FOR THE LABELMAP BEFORE IT GOES TO GPU
	//}
	
	run("Analyze Skeleton (2D/3D)", "prune=none");
	run("Clear Results");
	
	tagged_skeleton= "Tagged skeleton";
	selectImage(tagged_skeleton);
	setThreshold(29, 31);	//Gray value of endpoints is 30
	run("Convert to Mask", "background=Dark black create");
	rename("endpoints");
	
	skeleton = "skeleton";
	endpoints = "endpoints";
	skeleton = "skeleton";
	Ext.CLIJ2_push(skeleton);
	Ext.CLIJ2_push(endpoints);
	Ext.CLIJ2_push(labelmap);
	
	Ext.CLIJ2_dilateSphere(endpoints, endpoints_dilated);
//	Ext.CLIJ2_dilateLabels(endpoints, endpoints_dilated, endpoint_dilation_radius);
	Ext.CLIJ2_pullBinary(endpoints_dilated);
	run("Red");
	overlay_image_3D(labelmap, skeleton, 1, 100);
	overlay_image_3D(labelmap, endpoints_dilated, 1, 100);
	
	close("skeleton");
	close("Tagged skeleton");
	close(endpoints);
	close(endpoints_dilated);
	
	run("Clear Results");
	Ext.CLIJ2_getMaximumOfAllPixels(labelmap, nrLabels);
	Ext.CLIJ2_statisticsOfLabelledPixels(endpoints, labelmap);
	selectWindow("Results");
	if(Table.size == 0) continue;
	nr_endpoints = Table.getColumn("SUM_INTENSITY", "Results");
	nr_endpoints = divideArraybyScalar(nr_endpoints, 255);
	//nr_branches = subtract_scalar_from_array(nr_endpoints, 2);
	
	endpoint_distances = "endpoint_distances";
	Ext.CLIJx_morphoLibJDistanceToLabelBorderMap(labelmap, distance_to_border_map);
	Ext.CLIJ2_pull(distance_to_border_map);
	Ext.CLIJ2_mask(distance_to_border_map, endpoints, endpoint_distances);
	run("Clear Results");
	Ext.CLIJ2_statisticsOfLabelledPixels(endpoint_distances, labelmap);
	end_distances = Table.getColumn("SUM_INTENSITY", "Results");
	selectImage(distance_to_border_map);
	for (i=0; i<nrLabels; i++) {
		if(end_distances[i] == 0) {	//No skeleton -> Calculate twice the distance from centroid to edge
			end_distances[i] = (2 * Table.get("MAX_DISTANCE_TO_CENTROID", i) - 2);	//Subtract one pixel on each side
//			x = round(Table.get("CENTROID_X", i, "Results"));
//			y = round(Table.get("CENTROID_Y", i, "Results"));
//			z = round(Table.get("CENTROID_Z", i, "Results"));
//			Stack.setSlice(z+1);
//			end_distances[i] = 2 * getPixel(x,y);
		}
	}
	//Ext.CLIJ2_pull(endpoint_distances);
	
	// Actually, adding endpoints may not be fair. Microscope resolution (after AP) is >3 pixels, which is roughly the max distance to the edge (mostly 2)
	
	labeled_skeleton ="labeled_skeleton";
	Ext.CLIJ2_mask(labelmap, skeleton, labeled_skeleton);
	Ext.CLIJ2_pull(labeled_skeleton);
	run("glasbey_on_dark");
	setMinAndMax(0, 255);

	if(analyzeIn2D) {
		run("Analyze Regions", "area");
		//Table.rename("labeled_skeleton-Morphometry", "labeled_skeleton-morpho");
		morphoTable = getInfo("window.title");
		Table.renameColumn("Area", "VoxelCount", morphoTable);
	}
	else run("Analyze Regions 3D", "voxel_count surface_area_method=[Crofton (13 dirs.)] euler_connectivity=26");
	morphoTable = getInfo("window.title");
	skeleton_length = newArray(nrLabels);
	for (i=0; i<nrLabels; i++) {
		skeleton_length[i] = lookupInTable("Label", i+1, "VoxelCount", morphoTable);
	}
	close(morphoTable);
	
	Table.setColumn("SkeletonLength", skeleton_length, resultsTable);
	Table.setColumn("EndpointDistance", end_distances, resultsTable);
	total_length = addTableColumns(newArray("SkeletonLength","EndpointDistance"), resultsTable);
	for (i=0; i<nrLabels; i++) {
		if(nr_endpoints[i] == 1) {	//Only one endpoint -> Add another EndpointDistance
			total_length[i] += end_distances[i];
		}
	}
	Table.setColumn("TotalLength", total_length, resultsTable);
	
	Table.setColumn("NrEndpoints", nr_endpoints, resultsTable);
	//Table.setColumn("NrBranches", nr_branches, resultsTable);
	Table.update;
	
	Ext.CLIJ2_clear();
	
	//Save data
	selectImage(labelmap);
	saveAs("zip", outputFolder + File.separator + labelmap);
	Table.save(outputFolder + File.separator + labelmap + ".tsv");

	close(resultsTable);
}

Ext.CLIJ2_clear();
run("Close All");
run("Clear Results");

//Run this macro from Foci Analyzer
run("Combine result files", "filestring=tif.tsv dir=["+outputFolder+"], outputfilename=All_Results");


function overlay_image_3D(image, overlay, overlayChannel, opacity) {
	batchMode = is("Batch Mode");
	if(!batchMode) setBatchMode(true);
	selectImage(image);
	getDimensions(width, height, channels, slices, frames);
	Stack.setChannel(overlayChannel);
	Stack.getPosition(channel, slice, frame);
//	Overlay.clear;
	for (i = 1; i <= slices; i++) {
		selectImage(overlay);
		Stack.setSlice(i);
		selectImage(image);
		Stack.setSlice(i);
		run("Add Image...", "image=["+overlay+"] x=0 y=0 opacity="+opacity+" zero");
	}
	Stack.setPosition(channel, slice, frame);
	if(!batchMode) setBatchMode(false);
}

//Divides all elements of an array by a scalar
function divideArraybyScalar(array, scalar) {
	divided_array=newArray(lengthOf(array));
	for (a=0; a<lengthOf(array); a++) {
		divided_array[a]=array[a]/scalar;
	}
	return divided_array;
}

//Subtract a scalar from all elements of an array
function subtract_scalar_from_array(array, scalar) {
	subtracted_array=newArray(lengthOf(array));
	for (a=0; a<lengthOf(array); a++) {
		subtracted_array[a]=array[a] - scalar;
	}
	return subtracted_array;
}

//Returns, as array, all values in the column return_header that are in the same row as the lookup_value in the column ref_header
function lookupInTable(ref_header, lookup_value, return_header, table) {
	ref_column = Table.getColumn(ref_header);
	return_column = Table.getColumn(return_header);
	index = firstIndexOfArray(ref_column, lookup_value);
	if(index!=-1) return return_column[index];
	else return 0;
}

//Returns the first index at which a value occurs in an array
function firstIndexOfArray(array, value) {
	for (a=0; a<lengthOf(array); a++) {
		if (array[a]==value) {
			break;
		}
	}
	if(a<lengthOf(array)) return a;
	else return -1;
}

//Add multiple columns of a table element-wise. 'array' is a string array containing the array variable names
function addTableColumns(nameArray, table) {
	selectWindow(table);
	summed_Array = newArray(Table.size);
	for(i=0; i<Table.size; i++) {
		sum = 0;
		for (k = 0; k<nameArray.length; k++) {
			sum += Table.get(nameArray[k], i);
		}
		summed_Array[i] = sum;
	}
	return summed_Array;
}
