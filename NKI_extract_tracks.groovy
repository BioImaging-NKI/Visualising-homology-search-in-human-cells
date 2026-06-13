//@ ImagePlus (label = "Intensity image") intensityimp
//@ ImagePlus (label = "labelmap") labelimp
//@ Boolean (label = "Extract only nuclei tracks already present in frame 1", value=true) onlyfirst
//@ Boolean (label = "Save extracted tracks instead of displaying", value=true) savefiles
//@ Boolean (label = "Make composite images when showing tracks (slow)", value=false) makecomposite
//@ Boolean (label = "Convert output images to 16-bit", value=false) to16bit
//@ File (label = "Output directory", style = "directory") output

import ij.IJ
import ij.ImagePlus
import ij.plugin.Concatenator
import ij.process.ImageConverter
import net.haesleinhuepf.clij2.CLIJ2
import net.haesleinhuepf.clij2.plugins.StatisticsOfLabelledPixels.STATISTICS_ENTRY as se
import groovy.time.TimeCategory

ImagePlus intensityimp = intensityimp
ImagePlus labelimp = labelimp
params = new ExtractTracksParameters()
params.onlyfirst = onlyfirst
params.savefiles = savefiles
params.to16bit = to16bit
params.output = output
params.makecomposite = makecomposite

print(intensityimp)
print(labelimp)

def start = new Date()
extractTracks(intensityimp, labelimp, params)
def duration = TimeCategory.minus(new Date(), start)
IJ.log('took: ' +duration.toString())

class ExtractTracksParameters{
    Boolean to16bit
    Boolean onlyfirst
    Boolean savefiles
    Boolean makecomposite
    File output
    String toString(){
        return "Output: "+output
    }
}

static Void extractTracks(ImagePlus intensityimp, ImagePlus labelimp, ExtractTracksParameters params) {
    def dimsIntensity = intensityimp.getDimensions()  //width, height, nChannels, nSlices, nFrames
    def width = dimsIntensity[0]
    def height = dimsIntensity[1]
    def nChannels = dimsIntensity[2]
    def nSlices = dimsIntensity[3]
    if (nSlices>1){
        IJ.error('I am sorry but this script does not work if you have slices.')
        return
    }
    def nFrames = dimsIntensity[4]
    def dimsLabel = labelimp.getDimensions()
    if(nChannels>1){
        IJ.log('Found '+nChannels+' channels')
    }
    // Swap Z and T dimensions if T=1
    if (nFrames == 1) {intensityimp.setDimensions( dimsIntensity[2,4,3] )}
    if (dimsLabel[4] == 1) {labelimp.setDimensions( dimsLabel[2,4,3] )}
    // Check if dimensions agree
    dimsIntensity = intensityimp.getDimensions()
    dimsLabel = labelimp.getDimensions()
    if (dimsLabel[0]!=dimsIntensity[0]||dimsLabel[1]!=dimsIntensity[1]||dimsLabel[4]!=dimsIntensity[4]){
        IJ.error('ERROR: dimensions do not agree')
        return
    }
    // Swap channel and Z in intensity image to push multiple channels at once to GPU
    intensityimp.setDimensions(dimsIntensity[3,2,4])  //PUT BACK LATER AT END OF SCRIPT!!!
    // Add boundry with zeros for cropping out of image bounds
    IJ.run(intensityimp, "Canvas Size...", "width="+(width+2).toString()+" height="+(height+2).toString()+" position=Center zero")
    IJ.run(labelimp, "Canvas Size...", "width="+(width+2).toString()+" height="+(height+2).toString()+" position=Center zero")
    IJ.log('Final dimensions of intensityimp = ' +intensityimp.getDimensions())  // x-y-ch-z-t
    // Start analysis
    def clij2 = CLIJ2.getInstance()
    clij2.clear()
    def lbl_img_cl = clij2.push(labelimp)
    // Detect the largest bounding box in 2D
    def dimensions = clij2.getDimensions(lbl_img_cl)
    def imslice_lbl = clij2.create([lbl_img_cl.getWidth(), lbl_img_cl.getHeight()])
    int maxW = 0
    int maxH = 0
    for (int i=1; i<=dimensions[2]; i++){
        clij2.copySlice(lbl_img_cl, imslice_lbl, i)
        def stats = clij2.statisticsOfLabelledPixels(imslice_lbl, imslice_lbl)
        for (int j=0; j<stats.length ; j++){
            if (stats[j][se.BOUNDING_BOX_WIDTH.value]>maxW){maxW=(int)stats[j][se.BOUNDING_BOX_WIDTH.value]}
            if (stats[j][se.BOUNDING_BOX_HEIGHT.value]>maxH){maxH=(int)stats[j][se.BOUNDING_BOX_HEIGHT.value]}
        }
    }
    IJ.log('Largest boundingbox: W= ' +maxW.toString()+ ' ; H= ' +maxH.toString())
    // Get intensity in largest bounding box in 2D
    intensityimp.setSlice(0)
    def imslice_int = clij2.pushCurrentZStack(intensityimp)  //x-y-ch
    def roi_lbl_cl = clij2.create([maxW, maxH])
    def roi_int_cl = clij2.create([maxW, maxH, nChannels])
    def roi_msk_cl = clij2.create([maxW, maxH])
    def roi_int_msk_cl = clij2.create([maxW, maxH, nChannels])
    double x = 0
    double y = 0
    int current_track = 0
    LinkedHashMap<Integer, List<ImagePlus>> all_roi = []
    for (int i=1; i<=nFrames; i++){ //all frames
        clij2.copySlice(lbl_img_cl, imslice_lbl, i-1)
        intensityimp.setT(i)
        imslice_int = clij2.pushCurrentZStack(intensityimp)
        def stats = clij2.statisticsOfLabelledPixels(imslice_lbl, imslice_lbl)
        for (int j=0; j<stats.length ; j++){  // all labels
        	if (stats[j][se.BOUNDING_BOX_X.value]>1e90){continue}
            current_track = (int) stats[j][se.IDENTIFIER.value]
            if (current_track>0){
                // We should run this track only if we already have it or if the frame is 1 or if we should get all frames
                if (all_roi.containsKey(current_track) || i==1 || !params.onlyfirst) {
                    // if the boundingbox is smaller, center the crop
                    x = stats[j][se.BOUNDING_BOX_X.value] - (maxW - stats[j][se.BOUNDING_BOX_WIDTH.value]) / 2
                    y = stats[j][se.BOUNDING_BOX_Y.value] - (maxH - stats[j][se.BOUNDING_BOX_HEIGHT.value]) / 2
//                if (x < 0) {x = 0}
//                if (x > (dimensions[0]-maxW)){x = dimensions[0]-maxW}
//                if (y < 0) {y = 0}
//                if (y > (dimensions[1]-maxH)){y = dimensions[1]-maxH}
                    clij2.crop3D(imslice_lbl, roi_lbl_cl, x.round(), y.round(), 0)
                    clij2.crop3D(imslice_int, roi_int_cl, x.round(), y.round(), 0)
                    clij2.labelToMask(roi_lbl_cl, roi_msk_cl, current_track)
                    clij2.maskStackWithPlane(roi_int_cl, roi_msk_cl, roi_int_msk_cl)
                    if (all_roi.containsKey(current_track)) { // add to list or make a new one
                        all_roi[current_track].add(clij2.pull(roi_int_msk_cl))  //x-y-z(=channel)
                    } else {
                        all_roi[current_track] = [clij2.pull(roi_int_msk_cl)]
                    }
                }
            }
        }
    }

    def myConcatenator = new Concatenator()
    for (def entry : all_roi.entrySet()) {
        if (entry.getKey()>0) {
            def key = entry.getKey()
            def value = entry.getValue()
            ImagePlus[] myIpList = value.asList()
            ImagePlus myimp = myConcatenator.concatenate(myIpList, false)
            // rename, swap z<-->ch, convert back to 16-bit.
            myimp.setTitle('track_' + IJ.pad(key,3))
            def dimsTrack = myimp.getDimensions()
			myimp.setDimensions(dimsTrack[3,2,4])  //swap back Z and Channel
            if (params.to16bit){
				def ic = new ImageConverter(myimp)
				ic.setDoScaling(false)
				ic.convertToGray16()
			}
            if (params.savefiles){
                File myfile = new File(params.output, myimp.getTitle()+'.tif')
                IJ.save(myimp, myfile.toString())
                myimp.close()
            } else{
                myimp.show()
                IJ.run('View 100%', '')
                if(params.makecomposite) {
                    IJ.run("Make Composite", "display=Composite")
                    for (int i = 0; i < dimsTrack[3]; i++) {  // scale channels
                    	IJ.log(i.toString())
                        myimp.setC(i)
                        IJ.run(myimp, "Enhance Contrast", "saturated=0.35")
                    }
                }
            }

        }
    }
    intensityimp.setDimensions(dimsIntensity[3,2,4])  // put the intensity image z<->ch back
}