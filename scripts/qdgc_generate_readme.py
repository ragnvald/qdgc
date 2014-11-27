# FIle generates readme file based on data in batch-file.


import csv

f_readme_tpl  = ("C:/Users/RAGLAR/Desktop/GitHub/qdgc/templates/readme.tpl")
d_output      = ("C:/Users/RAGLAR/Desktop/GitHub/qdgc/output/")
f_batch_list  = ("C:/Users/RAGLAR/Desktop/GitHub/qdgc/output/batch_list.csv")


f = open(f_batch_list)

countries_list = csv.reader(f)


for country in countries_list:

	qdgc_level     = country[0]
	country_code   = country[1]
	country_name   = country[2]
	
	f_readme_txt = ('%s/qdgc_%s_%s_readme.txt') % (d_output,qdgc_level.zfill(2),country_code)
	
	infile = open(f_readme_tpl)
	outfile = open(f_readme_txt, 'a')
	
	for line in infile:
		line = line.replace("GIVE_LEVEL", qdgc_level)
		line = line.replace("GIVE_NAME", country_name)
		line = line.replace("GIVE_CODE", country_code)
		outfile.write(line)
	
	infile.close()
	
	outfile.close()