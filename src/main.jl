function PTree!(tree::AbstractDict)

    updateTree!(tree,
                "dir|file";
                action=Dict(
                    "d" => GUIloadICPdir!,
                    "p" => GUIloadICPfile!
                ))
    
end
export PTree!

function updateTree!(tree::AbstractDict,
                     key::AbstractString;
                     message=tree[key].message,
                     help=tree[key].help,
                     action=tree[key].action
                     )
    tree[key] = (message=message,help=help,action=action)
end
