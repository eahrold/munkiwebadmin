from django.conf.urls import patterns, include, url
from django.contrib.staticfiles.urls import staticfiles_urlpatterns
from django.conf import settings

# Uncomment the next two lines to enable the admin:
from django.contrib import admin
admin.autodiscover()

if settings.RUNNING_ON_APACHE:
    #The WSGIScriptAlias in the apache config file handles the subpathing so here it's blank
    sub_path = ''
else:
    sub_path= settings.SUB_PATH
    

urlpatterns = patterns('',
    # Uncomment the admin/doc line below to enable admin documentation:
    # url(r'^admin/doc/', include('django.contrib.admindocs.urls')),

    # Uncomment the next line to enable the admin:
    url(r'^admin/', include(admin.site.urls)),
    
    url(r'^%slogin/$'% sub_path, 'django.contrib.auth.views.login', name='login'),
    url(r'^%slogout/$'% sub_path, 'django.contrib.auth.views.logout_then_login', name='logout'),
    url(r'^%smanifest/'% sub_path, include('manifests.urls')),
    url(r'^%scatalog/'% sub_path, include('catalogs.urls')),
    url(r'^%sreport/'% sub_path, include('reports.urls')),
    url(r'^%sinventory/'% sub_path, include('inventory.urls')),
    url(r'^%slicenses/'% sub_path, include('licenses.urls')),
    # for compatibility with MunkiReport scripts
    url(r'^%supdate/'% sub_path, include('reports.urls')),
    url(r'^%slookup/'% sub_path, include('reports.urls')),
    url(r'^%s$'% sub_path, include('reports.urls')),
    url(r'^%s$'% sub_path, 'base', name='base')
)
# comment out the following if you are serving
# static files a different way
urlpatterns += staticfiles_urlpatterns()
