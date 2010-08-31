
if exists("g:loaded_vxlib") && g:loaded_vxlib
   finish
endif

" If a user wants to configure the plugins himself, he must add
"   let g:vxlib_user_generated_plugins=1
" to his .vimrc file. Otherwise the plugins will be automatically
" loaded from the directories vxlibautogen/plugin found in the
" runtimepath. It is the developers task to generate entries for
" each plugin using the plugin generator.
if !exists("g:vxlib_user_generated_plugins")
   let g:vxlib_user_generated_plugins=0
endif

if !g:vxlib_user_generated_plugins
   runtime! vxlibautogen/plugin/*.vim
else
   command! VxRegen call vxlib#pluggen#GeneratePlugins()
   command! VxConfig call vxlib#pluggen#ConfigurePlugins()
endif

