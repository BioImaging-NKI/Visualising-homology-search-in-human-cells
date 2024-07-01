# Visualising-homology-search-in-human-cells
Analysis scripts and object classifiers used in 'Visualising homology search in human cells' by Friskes et al.

![image](https://github.com/BioImaging-NKI/Visualising-homology-search-in-human-cells/assets/68109112/15997705-5c62-48b0-8100-3114d625bcae)

# Methods
## Macro’s to use:
* `Split_multiseries_files_and_z-project.ijm`
* `segment_3D_objects.ijm`
* `Crop_nuclei_and_objectMaps_for_Ilastik.ijm`
* `Append_result_files.ijm`

## Analysis Workflow:
1. Channel Extraction: Use the `Split_multiseries_files_and_z-project.ijm` macro to extract the single foci channel. Save the Z-stacks, including a maximum projection, in a separate folder for ease of access.
2. 3D Nuclear Segmentation: Apply the `segment_3D_objects.ijm` macro to the single-channel images with Z-stacks to perform 3D segmentation of the nuclei. Define a single setting and apply to all images.
3. Crop for Ilastik: Execute the `Crop_nuclei_and_objectMaps_for_Ilastik.ijm` macro to isolate individual nuclei to remove non-specific staining outside the nucleus.
4. Ilastik Training: Load the cropped images into Ilastik and train the program using several images. 
5. Batch Analysis in Ilastik: Run the trained model on all images. Make sure that the raw and corresponding segmented images are loaded c
6. Result Compilation: Use the `Append_result_files.ijm` macro to combine individual result files for subsequent analysis.

## Additional Note for 2D Analysis (Skeleton Length):
After running the `Crop_nuclei_and_objectMaps_for_Ilastik.ijm` macro, use the `Split_multiseries_files_and_z-project.ijm` macro again to generate Z-projections of the nuclei. (2D analysis in Ilastik) requires these projections.
