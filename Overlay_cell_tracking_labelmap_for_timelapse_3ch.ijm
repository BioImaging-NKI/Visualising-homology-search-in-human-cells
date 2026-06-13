#@ File[] (label = "Original image", style = "file") image_list
#@ File[] (label = "Labelmap", style = "file") labelmap_list
#@ File (label="Output folder", style = "directory") output_folder
#@ Float (label = "Overlay opacity (%)", value = 50) opacity
#@ Boolean (label = "Add cell numbers in output image", value = false) addNumbersOverlay
#@ String (label = "Add labels and numbers as", choices={"overlay","extra channel"}, style="radioButtonHorizontal") addOverlay
#@ Integer (label = "Cell numbers font size", value = 12, min = 1) labelFontSize
#@ ColorRGB(label = "Cell number font color", value="yellow") fontColor

run("CLIJ2 Macro Extensions", "cl_device=");
Ext.CLIJ2_clear();

for (f = 0; f < image_list.length; f++) {
	run("Close All");
	setBatchMode(false);
	open(image_list[f]);
	original = getTitle();
	bits = bitDepth();
	open(labelmap_list[f]);
	labelmap = getTitle();

	selectWindow(original);
	run("Remove Overlay");
	//Flip Huygens deconvoluted files
	if(matches(getTitle(), ".*cmle.ics.*") && !matches(getTitle(), ".*flipped*")) {
		run("Flip Vertically", "stack");
//		name = getTitle();
//		rename(substring(name, 0, lastIndexOf(name, ".tif")) + "_flipped.tif");
	}
	
	Stack.setChannel(2);
	run("Set Label...", "label=53BP1");
	run("Magenta");
	run("Enhance Contrast", "saturated=0.35");
	Stack.setChannel(1);
	run("Set Label...", "label=RPA");
	run("Green");
	run("Enhance Contrast", "saturated=0.35");
	Stack.setDisplayMode("composite");
	
	setBatchMode("hide");
	
	selectWindow(labelmap);
	getDimensions(width, height, channels, slices, frames);
	labelmap = getTitle();
	Ext.CLIJ2_push(labelmap);
	Ext.CLIJ2_getMaximumOfAllPixels(labelmap, maxLabel);
	//newImage("positions", "16-bit black", frames, maxLabel, 2);
	if(!isOpen("positions")) Table.create("positions");
	else Table.reset("positions");
	Table.showRowIndexes(true);
	
	for (i = 1; i <= frames; i++) {
		showStatus("Retrieving label positions... "+i+"/"+frames);
		showProgress(i, frames);
		selectWindow(labelmap);
		Stack.setFrame(i);
		Ext.CLIJ2_pushCurrentSlice(labelmap);
		Ext.CLIJ2_reduceLabelsToLabelEdges(labelmap, frameEdges);
		Ext.CLIJ2_dilateLabels(frameEdges, frameEdgesDilated, 1);
		Ext.CLIJ2_create3D(labelmapEdges, width, height, frames, 16);
		Ext.CLIJ2_copySlice(frameEdgesDilated, labelmapEdges, i-1);
		if(addNumbersOverlay) {
			run("Clear Results");
			Ext.CLIJ2_statisticsOfLabelledPixels(labelmap, labelmap);
			x = Table.getColumn("MASS_CENTER_X", "Results");
			y = Table.getColumn("MASS_CENTER_Y", "Results");
			Table.setColumn("x_"+i, x, "positions");
			Table.setColumn("y_"+i, y, "positions");
	
			//replace NaNs with '-', before they are automatically replaced by <blank>, leading to a failure in reading the rest of the column later.
			for (n = 0; n < x.length; n++) {
				if( isNaN(Table.get("x_"+i, n, "positions")) ) Table.set("x_"+i, n, "-", "positions");
				if( isNaN(Table.get("y_"+i, n, "positions")) ) Table.set("y_"+i, n, "-", "positions");
			}
		}
	}
	Table.update;
	
	Ext.CLIJ2_pull(labelmapEdges);
	Ext.CLIJ2_reportMemory();
	Ext.CLIJ2_clear();
	rename("overlay");
	run("Re-order Hyperstack ...", "channels=[Channels (c)] slices=[Frames (t)] frames=[Slices (z)]");	//Make a timelapse from he output z-stack
	run("glasbey_on_dark");
	setMinAndMax(0, 255);
	//setBatchMode("exit and display");
	run("Overlay Options...", "stroke=none width=0 fill=none set");
	if(addNumbersOverlay) {
		setFont("SansSerif", labelFontSize, "antialiased");
		color = color_to_hex(fontColor);
		setColor(color);
		run("Stack to Images");
		concatString = "";
		for (i = 1; i <= frames; i++) {
			selectWindow("overlay-"+IJ.pad(i,4));
			showStatus("Drawing overlay... "+i+"/"+frames);
			showProgress(i, frames);
			//Stack.setFrame(i);
			x = Table.getColumn("x_"+i, "positions");
			y = Table.getColumn("y_"+i, "positions");
			for (n = 0; n < x.length; n++) {
				drawString(n+1, x[n] - labelFontSize/2, y[n] + labelFontSize/2);
			}
			concatString+= " image"+i+"=overlay-"+IJ.pad(i,4);
			if(addOverlay == "overlay") {
				selectWindow(original);
				Stack.setFrame(i);
				run("Add Image...", "image=overlay-"+IJ.pad(i,4)+" x=0 y=0 opacity="+opacity+" zero");
			}
		}
		run("Concatenate...", concatString);
		rename("overlay");
		if(bitDepth() != bits) run(bits+"-bit");
	}
	
	selectWindow("overlay");
	setBatchMode("show");
	selectWindow(original);
	Stack.setFrame(1);
	setBatchMode("exit and display");

	if(addOverlay == "extra channel") {
		showStatus("Adding overlay channel...");
		run("Split Channels");
		run("Merge Channels...", "c1=[C1-"+original+"] c2=[C2-"+original+"] c3=[C3-"+original+"] c4=overlay create");
		rename("merged");
	}
	selectWindow("merged");
//	setBatchMode("show");

	//Have to flatten for large images - Saving messes up everything!
//	run("Flatten", "stack");
	saveAs("tif", output_folder + File.separator + File.getNameWithoutExtension(image_list[f]) + "_overlay");
}

function color_to_hex(color) {
	colorArray = split(color,",,");
	hexcolor = "#" + IJ.pad(toHex(colorArray[0]),2) + IJ.pad(toHex(colorArray[1]),2) + IJ.pad(toHex(colorArray[2]),2);
	return hexcolor;
}
