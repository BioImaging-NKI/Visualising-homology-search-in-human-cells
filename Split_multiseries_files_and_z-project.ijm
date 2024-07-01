/* Opens all series in multi-series files (e.g. .lif, .dv, .czi), makes (binned) projections and saves as .TIF files.
 * 
 * version 1.2 - October 2022:
 * - Added possibility to manually select a single slice instead of a projection
 * - Added possibility to automatically select the most intense slice (Mean intensity of the selected channel, measured in z)
 * - Added possibility to automatically select the sharpest slice (largest stddev of the selected channel, measured in z)
 * 
 * version 1.21 - October 2022:
 * - Binning now also applies to the non-projected image
 * 
 * version 1.22 - December 2022:
 * - Possibility to use virtual stack (saving memory for time-lapse movies)
 * 
 * version 1.3 - September 2023:
 * - Added feature to extract a single channel. Doesn't work together with 'Auto most intense slice' and 'Auto sharpest slice'.
 * 
 * Bram van den Broek (b.vd.broek@nki.nl), Netherlands Cancer Institute, 2014-2022
 * 
 * 
 */

version = 1.3;

#@File(label = "Input directory", style = "directory") input
#@File(label = "Output directory", style = "directory") output
#@String(label = "Input file extension", value = ".lif") fileExtension
#@Integer(label = "Extract only channel (-1 for all channels)", value=-1) extractChannel
#@Boolean(label = "Use virtual stack to save memory?", value=false) useVirtual
//#@String(label = "Output file format (Not yet implemented!)",choices={"TIFF", "OME-TIFF (retains all metadata)", "HDF5"}) output_format
#@String(value="<html><br>z-projection settings</br></html>", visibility="MESSAGE") message
#@Boolean(label = "Make z-projection", value=false) makeProjection
#@String(label = "Projection/selection type",choices={"Average Intensity", "Max Intensity", "Min Intensity", "Sum Slices", "Standard Deviation", "Median", "Select single slice", "Auto most intense slice", "Auto sharpest slice"}) projection_type
#@Integer(label = "Channel for 'Auto most intense slice'", value=1, min=1) auto_channel
#@Integer(label = "XY binning", value=1, min=1) binning
#@Boolean(label = "Also save not-projected series", value=false) save_not_projected

saveSettings();

print("\\Clear");
run("Clear Results");

var nr_series;
var file_name;
var format;

//define file suffix for every projection type
if (projection_type == "Average Intensity") projection_suffix = "_AVG";
if (projection_type == "Max Intensity") projection_suffix = "_MAX";
if (projection_type == "Min Intensity") projection_suffix = "_MIN";
if (projection_type == "Sum Slices") projection_suffix = "_SUM";
if (projection_type == "Standard Deviation") projection_suffix = "_STD";
if (projection_type == "Median") projection_suffix = "_MED";
if (projection_type == "Select single slice") projection_suffix = "_SLICE";
if (projection_type == "Auto most intense slice") projection_suffix = "_SLICE";

setBatchMode(true);

run("Bio-Formats Macro Extensions");

var nrOfImages=0;
var current_image_nr=0;
var processtime=0;
outputSubfolder = output;	//initialize this variable

if(!File.exists(output)) {
	create = getBoolean("The specified output folder "+output+" does not exist. Create?");
	if(create==true) File.makeDirectory(output);		//create the output folder if it doesn't exist
	else exit;
}

scanFolder(input);
processFolder(input);

restoreSettings();



//////////  FUNCTIONS  //////////

// function to scan folders/subfolders/files to count files with correct fileExtension
function scanFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(input + File.separator + list[i]))
			scanFolder(input + File.separator + list[i]);
		if(endsWith(list[i], fileExtension))
			nrOfImages++;
	}
	//print("Found " + nrOfImages + fileExtension + " files.\n\n");
}


// function to scan folders/subfolders/files to find files with correct fileExtension
function processFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(input + File.separator + list[i])) {
			outputFolder = output + File.separator + list[i];	
			if(!File.exists(outputSubfolder)) File.makeDirectory(outputSubfolder);	//create the output subfolder if it doesn't exist
			processFolder(input + File.separator + list[i]);
		}
		if(endsWith(list[i], fileExtension)) {
			current_image_nr++;
			showProgress(current_image_nr/nrOfImages);
			processFile(input, outputSubfolder, list[i]);
		}
	}
//	print("\\Clear");
	print("\\Update1:Finished processing "+nrOfImages+" files.");
	print("\\Update2:Average speed: "+d2s(current_image_nr/processtime,1)+" files per minute.");
	print("\\Update3:Total run time: "+d2s(processtime,1)+" minutes.");
	print("\\Update4:-------------------------------------------------------------------------");

}


function processFile(input, outputSubfolder, file) {
	if(nImages>0) run("Close All");
	roiManager("Reset");
	print("\\Clear");
	
	starttime = getTime();
	print("\\Update1:Processing file "+current_image_nr+"/"+nrOfImages+": " + input + File.separator + file);
	print("\\Update2:Average speed: "+d2s((current_image_nr-1)/processtime,1)+" files per minute.");
	time_to_run = (nrOfImages-(current_image_nr-1)) * processtime/(current_image_nr-1);
	if(time_to_run<5) print("\\Update3:Projected run time: "+d2s(time_to_run*60,0)+" seconds ("+d2s(time_to_run,1)+" minutes).");
	else if(time_to_run<60) print("\\Update3:Projected run time: "+d2s(time_to_run,1)+" minutes. You'd better get some coffee.");
	else if(time_to_run<480) print("\\Update3:Projected run time: "+d2s(time_to_run,1)+" minutes ("+d2s(time_to_run/60,1)+" hours). You'd better go and do something useful.");
	else if(time_to_run<1440) print("\\Update3:Projected run time: "+d2s(time_to_run,1)+" minutes. ("+d2s(time_to_run/60,1)+" hours). You'd better come back tomorrow.");
	else if(time_to_run>1440) print("\\Update3:Projected run time: "+d2s(time_to_run,1)+" minutes. This is never going to work. Give it up!");
	print("\\Update4:-------------------------------------------------------------------------");

	name = substring(file,0,lastIndexOf(file, "."));	//filename without extension
	name = replace(name,"\\/","-");	//replace slashes by dashes in the name
	name = replace(name," ","_");	//replace slashes by dashes in the name

	run("Close All");
	Ext.setId(input + File.separator + file);
	Ext.getSeriesCount(nr_series);

	for(i=0;i<nr_series;i++) {
		if(useVirtual) {
			if(extractChannel == -1) run("Bio-Formats Importer", "open=["+input + File.separator + file+"] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT use_virtual_stack series_"+i+1);
			else run("Bio-Formats Importer", "open=["+input + File.separator + file+"] autoscale color_mode=Default specify_range view=Hyperstack stack_order=XYCZT use_virtual_stack c_begin="+extractChannel+" c_end="+extractChannel+" c_step=1 series_"+i+1);
		}
		else {
			if(extractChannel == -1) run("Bio-Formats Importer", "open=["+input + File.separator + file+"] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT series_"+i+1);
			else run("Bio-Formats Importer", "open=["+input + File.separator + file+"] autoscale color_mode=Default specify_range view=Hyperstack stack_order=XYCZT c_begin="+extractChannel+" c_end="+extractChannel+" c_step=1 series_"+i+1);
		}
		seriesName = getTitle();
		seriesName = replace(seriesName,"\\/","-");	//replace slashes by dashes in the seriesName
		//run("Bio-Formats Exporter", "save=["+dir+seriesName+".ome.tif] compression=LZW");
//		print(input + File.separator + seriesName);
//		outputPath = output + File.separator + substring(seriesName,0,lastIndexOf(seriesName, "."));	//Doesn't quite do the job
		outputPath = output + File.separator + seriesName;

		// To do:
		// - Export in other file formats
		// - Read series names and only save as +i+1 if names are the same

		Ext.getSizeZ(sizeZ);
		if(sizeZ>1 && makeProjection==true) {
			if (projection_type != "Select single slice" && projection_type != "Auto most intense slice"  && projection_type != "Auto sharpest slice") {
				run("Z Project...", " projection=["+projection_type+"] all");
			}
			else if (projection_type == "Select single slice"){
				setBatchMode("show");
				waitForUser("Select slice and press OK");
				Stack.getPosition(channel, slice, frame);
				run("Duplicate...", "duplicate slices="+slice);
			}
			else if (projection_type == "Auto most intense slice") {
				getDimensions(width, height, channels, slices, frames);
				means = newArray(slices);
				Stack.setChannel(auto_channel);
				for (n = 0; n < slices; n++) {
					Stack.setSlice(n+1);
					means[n] = getValue("Mean");
				}
				maxPos = maxIndexOfArray(means);
				run("Duplicate...", "duplicate slices="+maxPos+1);
				projection_suffix = "_SLICE_"+maxPos+1;
			}
			else if (projection_type == "Auto sharpest slice") {
				getDimensions(width, height, channels, slices, frames);
				means = newArray(slices);
				Stack.setChannel(auto_channel);
				for (n = 0; n < slices; n++) {
					Stack.setSlice(n+1);
					means[n] = getValue("StdDev");
				}
				maxPos = maxIndexOfArray(means);
				run("Duplicate...", "duplicate slices="+maxPos+1);
				projection_suffix = "_SLICE_"+maxPos+1;
			}
			outputPathProjection = outputPath + "_" + projection_suffix;
			if(binning > 1) run("Bin...", "x="+binning+" y="+binning+" z="+binning+" bin=Average");
			if(!File.exists(outputPathProjection + ".tif")) saveAs("Tiff",outputPathProjection);	//Add i+1, because sometimes the series names are all the same (e.g. Tilescan experiments)
			else saveAs("Tiff",outputPathProjection + "_" +i+1);	//Add i+1, because sometimes the series names are all the same (e.g. Tilescan experiments)

			close();
		}
		if(save_not_projected==true) {
			if(binning > 1) run("Bin...", "x="+binning+" y="+binning+" bin=Average");
			if(!File.exists(outputPath + ".tif")) saveAs("Tiff",outputPath);	//Add i+1, because sometimes the series names are all the same (e.g. Tilescan experiments)
			else saveAs("Tiff",outputPath + "_" +i+1);	//Add i+1, because sometimes the series names are all the same (e.g. Tilescan experiments)
		}
		close();
	}
	current_image_nr++;
	
	endtime = getTime();
	processtime = processtime+(endtime-starttime)/60000;
}

restoreSettings();

//Returns the index of the maximum of an array
function maxIndexOfArray(array) {
	Array.getStatistics(array, min, max, mean, stdDev);
	index = indexOfArray(array, max);
	return index[0];
}


//Returns, as array, the indices at which a value occurs within an array
function indexOfArray(array, value) {
	count=0;
	for (a=0; a<lengthOf(array); a++) {
		if (array[a]==value) {
			count++;
		}
	}
	if (count>0) {
		indices=newArray(count);
		count=0;
		for (a=0; a<lengthOf(array); a++) {
			if (array[a]==value) {
				indices[count]=a;
				count++;
			}
		}
		return indices;
	}
}
