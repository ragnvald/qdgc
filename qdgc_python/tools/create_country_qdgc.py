import arcpy
from arcpy import env
import re
import os
import zipfile
import shutil

# file resources

f_countries   = ("E:/Dropbox/privat/prosjekter/qdgc/world_countries/ne_110m_admin_0_countries.shp")
f_qdgc        = ("E:/Dropbox/privat/prosjekter/qdgc/world_0_125.shp")
f_readme_tpl  = ("C:/Users/RAGLAR/Desktop/GitHub/qdgc/templates/readme.tpl")
d_output      = ("C:/temp/")



# Tell the system which level of QDGC we are working at

qdgc_level    = "03"

# Workspace
env.workspace = "C:/temp"


object_countrys        = "%s" % (f_countries)

countries_list = arcpy.UpdateCursor(object_countrys)


for country_one in countries_list:



	#Retrieve country information

	current_id       = country_one.getValue("FID")
	country_name     = str(country_one.getValue("SUBUNIT"))
	country_code     = str(country_one.getValue("ISO_A3"))
	country_code     = country_code.lower()
	
	if country_code<>"-99":

		print "Landkode %s" % (country_code)
	
		#Export feature to file
		
		evaluationstring     = "\"FID\" = %s" % (current_id)
		output_country       = "qdgc_%s.shp" % (country_code)
		arcpy.Select_analysis(object_countrys,output_country,evaluationstring)


		output_country_frame = "frame_qdgc_%s.shp" % (country_code)
		arcpy.MinimumBoundingGeometry_management(output_country,output_country_frame,"ENVELOPE", "NONE")
		
		arcpy.Delete_management(output_country)

		#Buffer ramme_:
		
		distanceField = "100000 meters"
		sideType = "FULL"
		endType  = "FLAT"

		output_country_frame_buffer = "buffer_frame_qdgc_%s.shp" % (country_code)
		arcpy.Buffer_analysis(output_country_frame, output_country_frame_buffer, distanceField, sideType, endType)
		
		arcpy.Delete_management(output_country_frame)
		
		#Select fra qdgc basert på ramme one
		
		
		arcpy.MakeFeatureLayer_management(f_qdgc, "fl_qdgc")
		
		arcpy.MakeFeatureLayer_management(output_country_frame_buffer, "fl_countrybuffer")
		
		arcpy.SelectLayerByLocation_management("fl_qdgc","intersect","fl_countrybuffer")
		
		#make folder based on country code
		full_country_export_path = ("%s%s") % (d_output,country_code)
		if not os.path.exists(full_country_export_path):
			os.makedirs(full_country_export_path)
		
		output_qdgc_raw = "%s%s/qdgc_%s_%s.shp" % (d_output,country_code,qdgc_level,country_code)
		
		arcpy.CopyFeatures_management("fl_qdgc", output_qdgc_raw)
		
		arcpy.Delete_management("fl_qdgc")
		arcpy.Delete_management("fl_countrybuffer")
		arcpy.Delete_management(output_country_frame_buffer)
		
		#Kopier template til destinasjonsfolder
		f_readme_txt = ('%s/readme_qdgc_%s_%s.txt') % (full_country_export_path,qdgc_level,country_code)
		
		infile = open(f_readme_tpl)
		outfile = open(f_readme_txt, 'a')
		
		for line in infile:
			line = line.replace("GIVE_LEVEL", qdgc_level)
			line = line.replace("GIVE_NAME", country_name)
			line = line.replace("GIVE_CODE", country_code)
			outfile.write(line)
		
		infile.close()
		
		outfile.close()
		
		
		#Pakk sammen

#Report finished
print "Ok"