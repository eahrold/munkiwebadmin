*please see the README.md at the root of this project for more general instructions on getting munkiwebadmin up and running*

#OS X Setup#

These are examples of how to configre munkiwebadmin on an OS X Mountian Lion Server (it should also work for Lion)  
It uses the webappctl control, but can also be used with the server app.

this project was forked with the intention of running on sub-path of /munkiwebadmin (eg http://your.server.com/munkiwebadmin).  Note the line in the included httpd_munkiwebadmin.conf file.

	WSGIScriptAlias /munkiwebadmin */path/to/your/*munkiwebadmin_env/munkiwebadmin/munkiwebadmin.wsgi


The other primary change in this fork was to allow for multiple django-wsgi apps to be run side-by side hence the renaming of /static/ directive in the settings.py file to /static_munkiwebadmin/.  With that set you can Alias more than one set of static files properly.

	Alias /static_munkiwebadmin/ */path/to/your/*munkiwebadmin_env/munkiwebadmin/static_munkiwebadmin/

####To install (on 10.8 )####
Edit munkiwebadmin.wsgi specifiying your virtualenv directory and place in 

	*/path/to/your/*munkiwebadmin_env/munkiwebadmin/

Now edit the httpd_munkiwebadmin.conf specifying the location of where you just placed the munkiwebadmin.wsgi file, and place that file in

	/Library/Server/Web/Config/apache2/

and finally edit the the com.aapps.munkiwebadmin.plist specifying the location of where you placed munkiwebadmin.wsgi, and place that file in

	/Library/Server/Web/Config/apache2/webapps/


