//@ ImagePlus myImp
//@ Boolean (label="ALLOW_TRACK_SPLITTING", value=false) allow_track_splitting
//@ Double (label="GAP_CLOSING_MAX_DISTANCE", value = 200) gap_closing_max_distance
//@ Double (label="LINKING_MAX_DISTANCE", value=200) linking_max_distance
//@ Integer (label="MAX_FRAME_GAP", value=3) max_frame_gap

import groovy.lang.GroovyClassLoader
import ij.IJ
import ij.ImagePlus

Double linking_max_distance = linking_max_distance
Double gap_closing_max_distance = gap_closing_max_distance
Boolean allow_track_splitting = allow_track_splitting
Integer max_frame_gap = max_frame_gap
ImagePlus myImp = myImp

def gcl = new GroovyClassLoader()
File file = new File(ij.Menus.getMacrosPath()+'NKI/trackmate_lblmap.groovy')
def clazz1 = gcl.parseClass(file)
def myclass = clazz1.newInstance()
ImagePlus myImp2 = myclass.run(myImp, linking_max_distance, gap_closing_max_distance, allow_track_splitting, max_frame_gap)
myImp2.show()
