//@ ImagePlus myImp
//@ Boolean touint16

import groovy.time.TimeCategory
import ij.IJ
import ij.ImagePlus
import ij.plugin.RGBStackMerge
import ij.plugin.Duplicator
import ij.plugin.ImageCalculator
import ij.process.ImageConverter

ImagePlus myImp = myImp
Boolean touint16 = touint16

def timeStart = new Date()
myImp = subtractMedianBg(myImp, touint16)
def timeStop = new Date()
def duration = TimeCategory.minus(timeStop, timeStart)
print('subtractMedianBg took: ' + duration)
myImp.show()

static ImagePlus subtractMedianBg(ImagePlus myImp, Boolean toUint16) {
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
        def subtracted = ImageCalculator.run(impChannel, impChannelMed, 'Subtract create 32-bit stack')
        impChannels.add(subtracted)
        impChannelMed.close()
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
    if(nChannels>1) impChannelBgs.setDisplayMode(IJ.COLOR)
    impChannelBgs.setTitle(title+'_MED')
    impChannelBgs.show()
    return impChannelBgs
}

