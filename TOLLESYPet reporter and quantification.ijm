/*
 * Macro for Natalia
 * Kind of based on methods in Katayama et al., 2020.
 *																					
 * Expected input is a/some multi-series containing z-stacks with two channels																					
 * Each series is opened in turn and user is directed to pick a z-slice to use for analysis
 * User then directed to draw ROIs from which background intensity is measured and subtracted from images for further processing
 * Ratio images are then created and area is measured based on various thresholds on the ratio images.
 * 																
 * 																					Written by Laura Murphy
 * 																					IGC Advanced Imaging Resource
 * 																					August 2021
 *																					
 *																					Altered Simon Wilkinson October 2021										
 */

 
//--------------------------------//-----------------------------------------------------------------------------------
//-- Setting up folders from user input, measurements and arrays to save results in 
//--------------------------------//-----------------------------------------------------------------------------------

inputFolder = getDirectory("Select the folder with your images");
outputFolder = getDirectory("Select the folder where you want to save the output");

run("Set Measurements...", "area mean standard min area_fraction limit display redirect=None decimal=3");

Filename = newArray();
Condition = newArray();
AreaRatio = newArray();
Threshold = newArray();

dirList = newArray();
dirList = getFileTree(inputFolder, dirList);

C1_XPoints = newArray();
C1_YPoints = newArray();
C2_XPoints = newArray();
C2_YPoints = newArray();

//--------------------------------//-----------------------------------------------------------------------------------
//-- Loop through each image file and then for each image file, loop through series count and do processing
//--------------------------------//-----------------------------------------------------------------------------------

for (f = 0; f < dirList.length; f++) { 

	run("Bio-Formats Macro Extensions");
	file = dirList[f];
	Ext.setId(dirList[f]);
	Ext.getSeriesCount(seriesCount);

	for (i = 1; i<=seriesCount; i++) { 
		run("Bio-Formats Importer", "open=&file autoscale color_mode=Default view=Hyperstack stack_order=XYCZT series_" + i);
    	Stack.getDimensions(width, height, channels, slices, frames); 
    	run("Enhance Contrast", "saturated=1");
    	// User chooses Z-slice to continue with, could be removed if only slices taken in future
    	waitForUser("Select Z-slice you want to continue with");

		// User can choose to skip image, could be removed if no longer needed
		Dialog.create("Skip image or continue?");
		Dialog.addCheckbox("Select to skip image", "Continue");
		Dialog.show();
		choice = Dialog.getCheckbox();
		
		if (choice == 1){
			run("Close");
			continue;
		}  else {
			
			Stack.getPosition(channel, slice, frame);
			run("Duplicate...", "duplicate slices=" + slice);
			
			title = getTitle();
			img = File.nameWithoutExtension;
			parts = split(title, "_");
			condition = parts[0];
			Condition = Array.concat(Condition, condition);

			// Make 32-bit for image calculation later (allow ratios), also small median filter to reduce noise
			run("32-bit");
			run("Median...", "radius=1");

			// Get user to select background ROIs and subtract the mean value of those ROIs from each channel
			run("Split Channels");
			selectWindow("C1-" + title);
			run("Enhance Contrast", "saturated=1");
			run("Specify...", "width=100 height=100 x=512 y=512 slice=1");
			waitForUser("Create 3 background squares in ROI Manager (tip: use 't' key)");
			roiManager("Deselect");
			roiManager("Measure");
			run("Summarize");
			subtraction = getResult("Mean", 3);
			run("Subtract...", "value=" + subtraction);
			resetMinAndMax();
			run("Clear Results");
			
			selectWindow("C2-" + title);
			run("Enhance Contrast", "saturated=0.35");
			roiManager("Measure");
			run("Summarize");
			subtraction = getResult("Mean", 3);
			run("Subtract...", "value=" + subtraction);	
			selectWindow("C2-" + title);
			resetMinAndMax();

			// Threshold image to make backgrounds NaNs
			setAutoThreshold("Huang dark stack");
			run("NaN Background");
			resetThreshold();
			selectWindow("C2-" + title);
			resetThreshold();

			// Create ratio image and save with magma LUT
			imageCalculator("Divide create 32-bit", "C1-" + title,"C2-" + title);
			run("mpl-magma", "display=[Result of C1-" + title + "] view=net.imagej.display.DefaultDatasetView@2a01d647");
			filename = img + "_Series_" + i;
			saveAs("Tiff", outputFolder + filename + "_Ratio.tif");
			run("Clear Results");
			rename("Ratio Image");

			// This can be modified by the user depending on the thresholds they want to be used for the TOLLES/YPet index. 
			
			step = 0;

			for (j=6; j<26; j++) {
				thrs = j / 8;
				selectWindow("Ratio Image");
				setThreshold(0, 1000000000000000000000000000000.0000);
				run("Measure");
				setThreshold(thrs, 1000000000000000000000000000000.0000);
				run("Create Selection");
				run("Measure");
				resetThreshold();
				run("Select None");

				fullArea = getResult("Area", step);
				step = step + 1;
				areaAboveThresh = getResult("Area", step);
				currentRatio = areaAboveThresh/fullArea;
				step = step + 1;

				Filename = Array.concat(Filename, filename);
				AreaRatio = Array.concat(AreaRatio, currentRatio);
				Threshold = Array.concat(Threshold, thrs);

			}
						
			// Setup for next images
			run("Close All");
			run("Clear Results");
			roiManager("Reset");
		}
	}
}

// Save results

	Array.show(Filename, Threshold, AreaRatio);
	saveAs("Results", outputFolder + File.separator + "Area Ratio Results.csv");
	run("Close");

//Python script then for visualising the data

//--------------------------------//-----------------------------------------------------------------------------------
//-- Tell user macro is done
//--------------------------------//-----------------------------------------------------------------------------------

Dialog.create("Progress");
Dialog.addMessage("Saving Complete!");
Dialog.show;

//--------------------------------//-----------------------------------------------------------------------------------
//-- Functions
//--------------------------------//-----------------------------------------------------------------------------------

function getFileTree(dir , fileTree){
	list = getFileList(dir);

	for(f = 0; f < list.length; f++){
		if (matches(list[f], "(?i).*\\.(tif|tiff|nd2|lif|ndpi|mvd2|ims|oib)$"))
			fileTree = Array.concat(fileTree, dir + list[f]);
		if(File.isDirectory(dir + File.separator + list[f]))
			fileTree = getFileTree(dir + list[f],fileTree);
	}
	return fileTree;
}
