//@ ImagePlus myImp
//@ Integer channel
//@ Float scaling
//@ Float (label="minimal size of labels (pix)", description=" ") min_label_size
//@ Float (label="maximum size of labels (pix)", description=" ") max_label_size
//@ Boolean remove_outliers
//@ Float outliers_radius
//@ Float outliers_threshold
//@ Float (label="StarDist probability threshold [0-1]", description="Lower threshold to accept more nuclei", value=0.5, min=0, max=1) starDist_prob
//@ Integer (label="Dilate labels with radius") dilate_labels_radius

import ij.IJ
import ij.ImagePlus
import groovy.json.JsonOutput
import ij.plugin.Duplicator
import ij.plugin.Concatenator
import net.haesleinhuepf.clij2.CLIJ2

ImagePlus myImp = myImp
Integer channel = channel
Float scaling = scaling
Float min_label_size = min_label_size
Float max_label_size = max_label_size
Boolean remove_outliers = remove_outliers
Float outliers_radius = outliers_radius
Float outliers_threshold = outliers_threshold
Float starDist_prob = starDist_prob

def labelProps = new LabelProps()
labelProps.m_minsize = min_label_size
labelProps.m_maxsize = max_label_size
def impChannel = new Duplicator().run(myImp, channel, channel, 1, 1, 1, myImp.getNFrames())
IJ.log(remove_outliers.toString())
if(remove_outliers) {
	IJ.log("Removing outliers with radius = "+outliers_radius+", threshold = "+outliers_threshold);
	IJ.run(impChannel, "Remove Outliers...", "radius="+outliers_radius+" threshold="+outliers_threshold+" which=Bright stack");
}
impChannel.setTitle(myImp.getTitle()+'_outliers_removed')
impChannel.show()
myImp = runStarDist(impChannel, scaling, labelProps, starDist_prob, dilate_labels_radius)
IJ.run("Re-order Hyperstack ...", "channels=[Channels (c)] slices=[Frames (t)] frames=[Slices (z)]");
myImp.show()

class LabelProps{
    float m_minsize	//nr of pixels
    float m_maxsize	//nr of pixels
    Void rescale(float scale){
        m_minsize = m_minsize * scale*scale
        m_maxsize = m_maxsize * scale*scale
        return
    }
    String toString(){
    	return "LabelProps: Minsize = "+m_minsize+" pixels; Maxsize = " + m_maxsize+ " pixels."
    }
}

static ImagePlus runStarDist(myImp, scaling, labelProps, starDist_prob, dilate_labels_radius) {
    labelProps.rescale(scaling)
    def dims = myImp.getDimensions()
    int newX = (int) (dims[0] * scaling)
    int newY = (int) (dims[1] * scaling)
    def myImpSc = myImp.resize(newX, newY, 'bilinear')
    myImpSc.setTitle(myImp.getTitle()+"_scaled")
    myImpSc.show()
    def args = ['input':myImpSc.getTitle(),
            'modelChoice':'Versatile (fluorescent nuclei)',
            'normalizeInput':'true',
            'percentileBottom':'1.0',
            'percentileTop':'99.8',
            'probThresh':starDist_prob.toString(),
            'nmsThresh':'0.4',
            'outputType':'Label Image',
            'nTiles':'1',
            'excludeBoundary':'2',
            'roiPosition':'Automatic',
            'verbose':'false',
            'showCsbdeepProgress':'false',
            'showProbAndDist':'false']
    def argsStr = JsonOutput.toJson(args)
    argsStr = argsStr.substring(1,argsStr.length()-1)  // remove curly brackets {}
    IJ.run('Command From Macro', 'command=[de.csbdresden.stardist.StarDist2D], args=[' +argsStr+ '], process=[false]')
    def lbl_img = IJ.getImage()
 
    def clij2 = CLIJ2.getInstance()

	//filter out small labels
    def lbl_img_cl = clij2.push(lbl_img)
    def lbl_img_filtered_cl = clij2.create(lbl_img_cl)
    clij2.excludeLabelsOutsideSizeRange(lbl_img_cl, lbl_img_filtered_cl, labelProps.m_minsize, labelProps.m_maxsize)
    def lbl_img_filtered = clij2.pull(lbl_img_filtered_cl)
    clij2.clear()

 	//upscale label image
    def lbl_img_resized = lbl_img_filtered.resize(dims[0], dims[1], 'none')
    lbl_img_resized.setCalibration(myImp.getCalibration().copy())
    IJ.run(lbl_img_resized, 'glasbey_on_dark', '')
    IJ.setMinAndMax(lbl_img_resized, 0, 255)

	//smooth labels by greyscale opening
	def lbl_img_frame_cl = clij2.create([dims[0], dims[1]])
	def lbl_img_frame_opened_cl = clij2.create([dims[0], dims[1]])
	def lbl_img_frame_opened_dilated_cl = clij2.create([dims[0], dims[1]])
	List<ImagePlus> label_img_final_list = []
	def lbl_img_resized_cl = clij2.push(lbl_img_resized)
	for(int i=0; i<dims[4]; i++) {
		clij2.copySlice(lbl_img_resized_cl, lbl_img_frame_cl, i)
		clij2.greyscaleOpeningSphere(lbl_img_frame_cl, lbl_img_frame_opened_cl, (1/scaling)+1, (1/scaling)+1, 0)
		clij2.dilateLabels(lbl_img_frame_opened_cl, lbl_img_frame_opened_dilated_cl, dilate_labels_radius)
		label_img_final_list.add(clij2.pull(lbl_img_frame_opened_dilated_cl))
	}
	ImagePlus[] label_img_final_imagePlusList = label_img_final_list.asList()
	def myConcatenator = new Concatenator()
	def label_img_final = myConcatenator.concatenate(label_img_final_imagePlusList, false)
    clij2.clear()
    return label_img_final
}
