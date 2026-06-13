# Visualising-homology-search-in-human-cells
Analysis scripts and object classifiers used in 'Visualising homology search in human cells' by Friskes et al.

![image](https://github.com/BioImaging-NKI/Visualising-homology-search-in-human-cells/assets/68109112/15997705-5c62-48b0-8100-3114d625bcae)

# 1. Analysis of foci/structures in fixed cells (3D)

### Analysis Workflow
1. Channel Extraction: Use the `Split_multiseries_files_and_z-project.ijm` macro to extract the single foci channel. Save the Z-stacks, including a maximum projection, in a separate folder for ease of access.
2. 3D Nuclear Segmentation: Apply the `segment_3D_objects.ijm` macro to the single-channel images with Z-stacks to perform 3D segmentation of the nuclei. Define a single setting and apply to all images.
3. Crop for Ilastik: Execute the `Crop_nuclei_and_objectMaps_for_Ilastik.ijm` macro to isolate individual nuclei to remove non-specific staining outside the nucleus.
4. Ilastik Training: Load the cropped images into Ilastik and train the program using several images. 
5. Batch Analysis in Ilastik: Run the trained model on all images. Make sure that the raw and corresponding segmented images are loaded c
6. Result Compilation: Use the `Append_result_files.ijm` macro to combine individual result files for subsequent analysis.

### Additional Note for 2D Analysis (Skeleton Length):
After running the `Crop_nuclei_and_objectMaps_for_Ilastik.ijm` macro, use the `Split_multiseries_files_and_z-project.ijm` macro again to generate Z-projections of the nuclei. (2D analysis in Ilastik) requires these projections.


# 2. Analysis of structures in timelapse live-cell images (3D+t / 2D+t)

### Analysis Workflow:
1.	(Optional) Deconvolve 3D timelapse images (Huygens Proffesional)
2.	`Split_multiseries_files_and_z-project.ijm`: Read .czi files with Bio-Formats and create maximum intensity z-projection timelapse images.
3.	`Preprocess_segment_track_extract_and_register_nuclei.ijm`: This macro performs preprocessing, nuclei segmentation, nuclei tracking and image registration to stabilize the movement of individual nuclei.
    - Subtract median (static background, moving nuclei).
    - Add all channels (no nuclei marker, so we need all the photons we can get from the foci channels), remove outliers (the foci) and segment nuclei with StarDist for all time frames.
    - Run Trackmate on the resulting labelmap, resulting in a ‘tracked labelmap’.
    - Extract single nuclei tracks from the original timelapses.
    - Register the single nuclei images using a rigid body transformation to correct for nuclei rotation and drift (HyperStackReg plugin).
    For each nucleus, single nuclei registered tracked images on a black background (extracted from the deconvolved images) are saved, as well as a full-image tracked labelmap.

  	https://github.com/user-attachments/assets/c087e09e-0d90-440b-817d-82b74cd24343

    https://github.com/user-attachments/assets/dd58467c-4f9f-4935-9e7a-3245dc91a090

4.	`Overlay_cell_tracking_labelmap_for_timelapse_3ch.ijm`: Overlays the nucleus outlines from the tracked labelmap with track numbers on timelapse images; this is useful for visual inspection of the tracking results, as well as for selection of tracked nuclei for downstream analysis.
5.	zeropad_tracks_and_combine_registration.ijm:
    - Fix file naming by trackmate (1 -> 001, etc.)
    - Combine tracked single nuclei and registered single nuclei timelapse images for visualization of the registration results

    https://github.com/user-attachments/assets/8c55ddfa-ae35-4e34-8655-a47049067d1e

6.	`Segment_with_labkit_and_merge.ijm`: Segment 53BP1 foci or RAD51 structures with LabKit pixel classifier, resulting in a binary timelapse or a 3D z-stack mask, depending on the input. It runs an existing LabKit classifier file, extracts the segmented mask and merges it as channel (red) with the selected segmentation channel of the original image (grays).
7.	For timelapse images: run TrackMate on the timelapse mask from Labkit to follow individual foci/structures within each nucleus.
    
    <img width="240" height="240" alt="Path from ID2695 to ID2585_track4-3" src="https://github.com/user-attachments/assets/87cc3e61-0f8e-4fb5-be2e-d4708cb5aabe" />
    
8.	For 3D (fixed images) Connected component analysis on the segmented masks from Labkit to create 3D object maps, plus maximum intensity projections for 2D analysis. Optionally use `Split_multiseries_files_and_z-project.ijm` again to create maximum intensity z-projections for analysis of the structures in 2D.
9.	`Skeletonize_and_measure_labels.ijm`: Skeletonize the label images with structures (2D / 3D), and measure length and shape features using CLIJ and MorphoLibJ. Due to the width of the structures the skeletons do not stretch all the way to the ends. Roundish structures sometimes ends up with a very small skeleton length, even a single pixel. This effect is compensated in the  'Totallength' output:
    - For every endpoint the shortest distance to the edge of the label is added to the skeleton length.
    - For structures with only 1 endpoint (near circles or spheres), this distance is added twice.
    <br>
    <img width="400" alt="Skeletonized_objects_2D" src="https://github.com/user-attachments/assets/83e1da34-73a9-4893-98c9-658844dd97ee" />
    <img width="675" alt="image" src="https://github.com/user-attachments/assets/009c15a1-c80c-486a-a270-4782032316d1" />

10. `Append_result_files.ijm`: combine individual results files for subsequent analysis.
