# Pack files in folders and zip'em!

import os
import csv
import glob
import shutil
import subprocess

d_output_root  = ("C:/Users/RAGLAR/Desktop/GitHub/qdgc/output/")
f_batch_list   = ("C:/Users/RAGLAR/Desktop/GitHub/qdgc/output/batch_list.csv")


f = open(f_batch_list)

countries_list = csv.reader(f)


for country in countries_list:

	qdgc_level     = country[0]
	country_code   = country[1]
	country_name   = country[2]
	
	d_output_country = ('%sqdgc_%s') % (d_output_root,country_code)
	
	if not os.path.exists(d_output_country):
	    os.makedirs(d_output_country)	
	    
	filematch_dbf = ('%sqdgc_??_%s.dbf') % (d_output_root,country_code)	    

	for dbf_name in glob.glob(filematch_dbf):
		
		# Path to file. Must have columns LON, LAT and QDGC. LON/LAT types
		# should be set to N (numeric). ArcGis normaly sets it to F instead.
		# Can easily be changed in an editor with hex edit capabilities.
		string_commandline = ('lonlat2qdgc.exe %s %s')  % (dbf_name,qdgc_level )
		
		subprocess.call(string_commandline, shell=True)


	filematch = ('%sqdgc_??_%s*.*') % (d_output_root,country_code)
	      
	for name in glob.glob(filematch):
		
	     shutil.move(name, d_output_country)
	     
