//@ ImagePlus myImp
//@ Boolean touint16
//@ Boolean correctBleaching

import groovy.time.TimeCategory
import ij.IJ
import ij.ImagePlus
import ij.plugin.RGBStackMerge
import ij.plugin.Duplicator
import ij.plugin.ImageCalculator
import ij.process.ImageConverter
import net.haesleinhuepf.clij2.CLIJ2


ImagePlus myImp = myImp
Boolean touint16 = touint16
Boolean correctBleaching = correctBleaching

def timeStart = new Date()
myImp = subtractMedianBg(myImp, touint16, correctBleaching)
def timeStop = new Date()
def duration = TimeCategory.minus(timeStop, timeStart)
print('subtractMedianBg took: ' + duration)
//IJ.run("Re-order Hyperstack ...", "channels=[Channels (c)] slices=[Frames (t)] frames=[Slices (z)]");
def dims = myImp.getDimensions()  //width, height, nChannels, nSlices, nFrames
myImp.setDimensions(dims[2,4,3])
myImp.show()

static ImagePlus subtractMedianBg(ImagePlus myImp, Boolean toUint16, correctBleaching) {
    def title = myImp.getTitle()
    def dimensions = myImp.getDimensions()
    def width = dimensions[0]
    def height = dimensions[1]
    def nChannels = dimensions[2]
    def nSlices = dimensions[3]
    def nFrames = dimensions[4]
    List<ImagePlus> impChannels = []
    for (int ch=1; ch<=dimensions[2];ch++){
        def impChannel = new Duplicator().run(myImp, ch, ch, 1, 1, 1, myImp.getNFrames())
        IJ.run(impChannel, 'Z Project...', 'projection=Median')
        def impChannelMed = IJ.getImage()

		//subtract median
		def impChannel_subtr = ImageCalculator.run(impChannel, impChannelMed, 'Subtract create 32-bit stack')
        impChannelMed.close()
		impChannel.close()

        //Bleach correction on GPU
		if(correctBleaching) {
	        def clij2 = CLIJ2.getInstance()
			def impChannel_cl = clij2.push(impChannel_subtr)
	
			def impChannel_cl_eq = clij2.create(impChannel_cl)
			clij2.equalizeMeanIntensitiesOfSlices(impChannel_cl, impChannel_cl_eq, 0)
			def impChannel_eq = clij2.pull(impChannel_cl_eq)
			clij2.clear()
			impChannels.add(impChannel_eq)
		}
		else impChannels.add(impChannel_subtr)
    }
    ImagePlus[] myIpList = impChannels.asList()
    def impChannelBgs = myIpList[0]
    if(myIpList.size() > 1) {
	    def myRGBStackMerge = new RGBStackMerge()
	    impChannelBgs = myRGBStackMerge.mergeHyperstacks(myIpList, false)
    }
    if (toUint16){
        def ic = new ImageConverter(impChannelBgs)
        ic.setDoScaling(false)
        ic.convertToGray16()
    }
    impChannelBgs.setDisplayMode(IJ.COLOR)
    impChannelBgs.setTitle(title+'_bgsubtr_bleachcorr')
    impChannelBgs.show()
    return impChannelBgs
}

