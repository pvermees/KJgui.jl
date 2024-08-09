function extend!(_PT::AbstractDict)

    _PT["ctrl"]["gui"] = GtkWindow("Plasmatrace",-1,-1,true,false)
    
    updateTree!(_PT["tree"],
                "dir|file";
                action=Dict(
                    "d" => GUIloadICPdir!,
                    "p" => GUIloadICPfile!
                ))
        
end
export extend!

function updateTree!(tree::AbstractDict,
                     key::AbstractString;
                     message=tree[key].message,
                     help=tree[key].help,
                     action=tree[key].action
                     )
    tree[key] = (message=message,help=help,action=action)
end
