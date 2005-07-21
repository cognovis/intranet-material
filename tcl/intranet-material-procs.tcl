# /packages/intranet-material/tcl/intranet-material.tcl
#
# Copyright (C) 2003-2004 Project/Open
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    @author frank.bergmann@project-open.com
}


# ----------------------------------------------------------------------
# Category Constants
# ----------------------------------------------------------------------

ad_proc -public im_material_status_active { } { return 9100 }
ad_proc -public im_material_status_inactive { } { return 9102 }

ad_proc -public im_material_type_software_dev { } { return 9000 }
ad_proc -public im_material_type_software_testing { } { return 9002 }


ad_proc -public im_package_material_id {} {
    Returns the package id of the intranet-material module
} {
    return [util_memoize "im_package_material_id_helper"]
}

ad_proc -private im_package_material_id_helper {} {
    return [db_string im_package_core_id {
        select package_id from apm_packages
        where package_key = 'intranet-material'
    } -default 0]
}



# ----------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------

ad_proc -private im_material_type_options { {-include_empty 1} } {

    set options [db_list_of_lists material_type_options "
        select category, category_id
        from im_categories
        where category_type = 'Intranet Material Type'
    "]
    if {$include_empty} { set options [linsert $options 0 { "" "" }] }
    return $options
}

ad_proc -private im_material_status_options { {-include_empty 1} } {

    set options [db_list_of_lists material_status_options "
        select category, category_id
        from im_categories
        where category_type = 'Intranet Material Status'
    "]
    if {$include_empty} { set options [linsert $options 0 { "" "" }] }
    return $options
}


# Get a list of available materials
ad_proc -private im_material_options { {-restrict_to_status_id 0} {-restrict_to_type_id 0} {-include_empty 1} } {

    set where_clause ""
    if {0 != $restrict_to_status_id} {
	append where_clause "material_status_id = :-restrict_to_status_id\n"
    }
    if {0 != $restrict_to_type_id} {
	append where_clause "material_type_id = :-restrict_to_type_id\n"
    }

    set options [db_list_of_lists material_options "
        select material_nr, material_id
        from im_materials
        where 
		1=1
		$where_clause
	order by
		material_nr
    "]
    if {$include_empty} { set options [linsert $options 0 { "" "" }] }
    return $options
}



# ----------------------------------------------------------------------
# Material List Page Component
# ---------------------------------------------------------------------

ad_proc -public im_material_list_component {
    {-view_name ""} 
    {-order_by "priority"} 
    {-restrict_to_type_id 0} 
    {-restrict_to_status_id 0} 
    {-max_entries_per_page 50} 
    {-start_idx 0} 
    -user_id 
    -current_page_url 
    -return_url 
    -export_var_list
} {
    Creates a HTML table showing a table of Materials 
} {
    set bgcolor(0) " class=roweven"
    set bgcolor(1) " class=rowodd"
    set date_format "YYYY-MM-DD"

    set max_entries_per_page 50
    set end_idx [expr $start_idx + $max_entries_per_page - 1]

    if {![im_permission $user_id view_materials]} { return ""}

    set view_id [db_string get_view_id "select view_id from im_views where view_name=:view_name" -default 0]
    if {0 == $view_id} {
	# We haven't found the specified view, so let's emit an error message
	# and proceed with a default view that should work everywhere.
	ns_log Error "im_material_component: we didn't find view_name=$view_name"
	set view_name "material_list"
	set view_id [db_string get_view_id "select view_id from im_views where view_name=:view_name"]
    }

    # ---------------------- Get Columns ----------------------------------
    # Define the column headers and column contents that
    # we want to show:
    #
    set column_headers [list]
    set column_vars [list]

    set column_sql "
	select
	        column_name,
	        column_render_tcl,
	        visible_for
	from
	        im_view_columns
	where
	        view_id=:view_id
	        and group_id is null
	order by
	        sort_order
    "

    db_foreach column_list_sql $column_sql {
	if {"" == $visible_for || [eval $visible_for]} {
        lappend column_headers "$column_name"
        lappend column_vars "$column_render_tcl"
	}
    }
    ns_log Notice "im_material_component: column_headers=$column_headers"

    # -------- Compile the list of parameters to pass-through-------

    set form_vars [ns_conn form]
    if {"" == $form_vars} { set form_vars [ns_set create] }

    set bind_vars [ns_set create]
    foreach var $export_var_list {
        upvar 1 $var value
        if { [info exists value] } {
            ns_set put $bind_vars $var $value
            ns_log Notice "im_material_component: $var <- $value"
        } else {
        
            set value [ns_set get $form_vars $var]
            if {![string equal "" $value]} {
 	        ns_set put $bind_vars $var $value
 	        ns_log Notice "im_material_component: $var <- $value"
            }
            
        }
    }

    ns_set delkey $bind_vars "order_by"
    ns_set delkey $bind_vars "start_idx"
    set params [list]
    set len [ns_set size $bind_vars]
    for {set i 0} {$i < $len} {incr i} {
        set key [ns_set key $bind_vars $i]
        set value [ns_set value $bind_vars $i]
        if {![string equal $value ""]} {
            lappend params "$key=[ns_urlencode $value]"
        }
    }
    set pass_through_vars_html [join $params "&"]

    # ---------------------- Format Header ----------------------------------

    # Set up colspan to be the number of headers + 1 for the # column
    set colspan [expr [llength $column_headers] + 1]

    # Format the header names with links that modify the
    # sort order of the SQL query.
    #
    set table_header_html "<tr>\n"
    foreach col $column_headers {

	set cmd_eval ""
	ns_log Notice "im_material_component: eval=$cmd_eval $col"
	set cmd "set cmd_eval $col"
        eval $cmd
	if { [regexp "im_gif" $col] } {
	    set col_tr $cmd_eval
	} else {
	    set col_tr [_ intranet-material.[lang::util::suggest_key $cmd_eval]]
	}

	if { [string compare $order_by $cmd_eval] == 0 } {
	    append table_header_html "  <td class=rowtitle>$col_tr</td>\n"
	} else {
	    append table_header_html "  <td class=rowtitle>
            <a href=$current_page_url?$pass_through_vars_html&order_by=[ns_urlencode $cmd_eval]>$col_tr</a>
            </td>\n"
	}
    }
    append table_header_html "</tr>\n"


    # ---------------------- Build the SQL query ---------------------------

    set order_by_clause "order by m.material_nr"
    set order_by_clause_ext "order by material_nr"
    switch [string tolower $order_by] {
	"nr" { 
	    set order_by_clause "order by m.material_nr" 
	    set order_by_clause_ext "order by material_nr"
	}
	"name" { 
	    set order_by_clause "order by m.material_name" 
	    set order_by_clause_ext "order by material_name"
	}
	"type" { 
	    set order_by_clause "order by m.material_type_id, m.material_nr" 
	    set order_by_clause_ext "order by material_type_id, material_nr"
	}
	"uom" { 
	    set order_by_clause "order by m.material_uom_id" 
	    set order_by_clause_ext "order by material_uom_id"
	}
    }
	
	
    set restrictions [list]
    if {$restrict_to_status_id} {
	lappend criteria "m.material_status_id in (
        	select :material_status_id from dual
        	UNION
        	select child_id
        	from im_category_hierarchy
        	where parent_id = :material_status_id
        )"
    }
    if {$restrict_to_type_id} {
	lappend criteria "m.material_type_id in (
        	select :material_type_id from dual
        	UNION
        	select child_id
        	from im_category_hierarchy
        	where parent_id = :material_type_id
        )"
    }

    set restriction_clause [join $restrictions "\n\tand "]
    if {"" != $restriction_clause} { 
	set restriction_clause "and $restriction_clause" 
    }
    set restriction_clause "1=1 $restriction_clause"
    ns_log Notice "im_material_component: restriction_clause=$restriction_clause"
		
    set material_statement [db_qd_get_fullname "material_query" 0]
    set material_sql_uneval [db_qd_replace_sql $material_statement {}]
    set material_sql [expr "\"$material_sql_uneval\""]
	
    # ---------------------- Limit query to MAX rows -------------------------
    
    # We can't get around counting in advance if we want to be able to
    # sort inside the table on the page for only those rows in the query 
    # results
    
    set limited_query [im_select_row_range $material_sql $start_idx [expr $start_idx + $max_entries_per_page]]
    set total_in_limited_sql "select count(*) from ($material_sql) f"
    set total_in_limited [db_string total_limited $total_in_limited_sql]
    set selection "select z.* from ($limited_query) z $order_by_clause_ext"
    
    # How many items remain unseen?
    set remaining_items [expr $total_in_limited - $start_idx - $max_entries_per_page]
    ns_log Notice "im_material_component: total_in_limited=$total_in_limited, remaining_items=$remaining_items"
    
    # ---------------------- Format the body -------------------------------
    
    set table_body_html ""
    set ctr 0
    set idx $start_idx
    set old_material_type_id 0
	
    db_foreach material_query_limited $selection {
	
	# insert intermediate headers for every material type
	if {[string equal "Type" $order_by]} {
	    if {$old_material_type_id != $material_type_id} {
		append table_body_html "
    	            <tr><td colspan=$colspan>&nbsp;</td></tr>
    	            <tr><td class=rowtitle colspan=$colspan>
    	              <A href=index?[export_url_vars material_type_id project_id]>
    	                $material_type
    	              </A>
    	            </td></tr>\n"
		set old_material_type_id $material_type_id
	    }
	}
	
	append table_body_html "<tr$bgcolor([expr $ctr % 2])>\n"
	foreach column_var $column_vars {
	    append table_body_html "\t<td valign=top>"
	    set cmd "append table_body_html $column_var"
	    eval $cmd
	    append table_body_html "</td>\n"
	}
	append table_body_html "</tr>\n"
	
	incr ctr
	if { $max_entries_per_page > 0 && $ctr >= $max_entries_per_page } {
	    break
	}
    }
    # Show a reasonable message when there are no result rows:
    if { [empty_string_p $table_body_html] } {
	set table_body_html "
		<tr><td colspan=$colspan align=center><b>
		[_ intranet-material.There_are_no_active_materials]
		</b></td></tr>"
    }
    
    if { $ctr == $max_entries_per_page && $end_idx < [expr $total_in_limited - 1] } {
	# This means that there are rows that we decided not to return
	# Include a link to go to the next page
	set next_start_idx [expr $end_idx + 1]
	set next_page_url  "$current_page_url?[export_url_vars max_entries_per_page order_by]&start_idx=$next_start_idx&$pass_through_vars_html"
	set next_page_html "($remaining_items more) <A href=\"$next_page_url\">&gt;&gt;</a>"
    } else {
	set next_page_html ""
    }
    
    if { $start_idx > 0 } {
	# This means we didn't start with the first row - there is
	# at least 1 previous row. add a previous page link
	set previous_start_idx [expr $start_idx - $max_entries_per_page]
	if { $previous_start_idx < 0 } { set previous_start_idx 0 }
	set previous_page_html "<A href=$current_page_url?$pass_through_vars_html&order_by=$order_by&start_idx=$previous_start_idx>&lt;&lt;</a>"
    } else {
	set previous_page_html ""
    }
    

    # ---------------------- Join all parts together ------------------------

    set component_html "
<table bgcolor=white border=0 cellpadding=1 cellspacing=1>
  $table_header_html
  $table_body_html
</table>
"

    return $component_html
}
