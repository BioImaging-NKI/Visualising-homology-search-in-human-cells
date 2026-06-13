#@ File (label = "Input directory", style = "directory") inputFolder
#@ File (label = "Output directory", style = "directory") outputFolder

print("\\Clear");
run("Close All");

setBatchMode(true)

list = getFileList(inputFolder);
Array.print(list);

//Remove directories and already combined files from the list
for (i = list.length-1; i >= 0; i--) {
	if(File.isDirectory(inputFolder + File.separator + list[i])) list = Array.deleteIndex(list, i);
	if(list[i].matches(".*combined.*")) list = Array.deleteIndex(list, i);
}

//Add zero padding
for (i = 0; i < list.length; i++) {
//	print( substring( list[i], lastIndexOf(list[i], "_") );
	if(list[i].matches(".*registered.*")) new_name = substring(list[i], 0, lastIndexOf(list[i], "track_")+6) + IJ.pad(substring(list[i], lastIndexOf(list[i], "track_")+6, lastIndexOf(list[i], "_registered")),3) + "_registered.tif";
	else new_name = substring(list[i], 0, lastIndexOf(list[i], "track_")+6) + IJ.pad(substring(list[i], lastIndexOf(list[i], "track_")+6, lastIndexOf(list[i], ".")),3) + ".tif";
	File.rename(inputFolder + File.separator + list[i], inputFolder + File.separator + new_name);
}

list = getFileList(inputFolder);
//Remove directories and already combined files from the list
for (i = list.length-1; i >= 0; i--) {
	if(File.isDirectory(inputFolder + File.separator + list[i])) list = Array.deleteIndex(list, i);
	if(list[i].matches(".*combined.*")) list = Array.deleteIndex(list, i);
}

Array.sort(list);

largest_nr_frames = 0;
for (i = 0; i < list.length; i=i+2) {
	showProgress(i, list.length);
	open(inputFolder + File.separator + list[i]);
	image_org = getTitle();
	open(inputFolder + File.separator + list[i+1]);
	image_reg = getTitle();
	getDimensions(width, height, channels, slices, frames);
	largest_nr_frames = maxOf(largest_nr_frames, frames);
	run("Combine...", "stack1="+image_org+" stack2="+image_reg);
	rename(substring(image_org, 0, lastIndexOf(image_org, ".")));

	Stack.setChannel(2);
	run("Set Label...", "label=53BP1");
	run("Magenta");
	run("Enhance Contrast", "saturated=0.35");
	getMinAndMax(min, max);
	setMinAndMax(0, 20);
	Stack.setChannel(1);
	run("Set Label...", "label=RPA");
	run("Green");
	run("Enhance Contrast", "saturated=0.35");
	getMinAndMax(min, max);
	setMinAndMax(0, minOf(max, 20));
	Stack.setDisplayMode("composite");

	name = File.getNameWithoutExtension(inputFolder + File.separator + list[i]) + "_combined";
	saveAs("tif", outputFolder + File.separator + name);
}
