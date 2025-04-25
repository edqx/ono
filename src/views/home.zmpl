<div class="filter">
    <div class="filter-sections">
        <div class="filter-section">
            <strong>Search Query</strong>
            <input id="filter-query" class="filter-query" onkeyup="onSearchKeyPress(event)" value="{{ $.filter_query }}" placeholder="Enter Query.."/>
            <button class="filter-action_right" onclick="updateSearchQuery()">Search</button>
        </div>
        <div class="filter-section">
            <strong>Filter Tags</strong>
            @zig {
                const filter_tags3 = try zmpl.coerceArray("filter_tags");
                @if (filter_tags3.len > 0)
                    <div class="tags_list">
                        @for (filter_tags3) |filter_tag| {
                            <div class="tag">
                                <span>{{ filter_tag }}</span>
                                <div class="tag-quick_actions">
                                    <a href="#" onclick="removeTag('{{ filter_tag }}')">[rem]</a>
                                </div>
                            </div>
                        }
                    </div>
                @end
            }
            <select id="filter-add_tag" class="filter-action_left" onchange="addSelectedTag()">
                <option></option>
                @zig {
                    const all_tags = try zmpl.coerceArray("all_tags");
                    const filter_tags = try zmpl.coerceArray("filter_tags");
                    for (all_tags) |tag| {
                        const has_tag = for (filter_tags) |filter_tag| {
                            if (filter_tag.eql(tag.*)) break true;
                        } else false;
                        @if (!has_tag)
                            <option value="{{ tag }}">{{ tag }}</option>
                        @end
                    }
                }
            </select>
        </div>
        <div class="filter-section">
            <strong>Filter Assigned To</strong>
            <select id="filter-assigned_to" class="filter-action_left" onchange="setSelectedAssignedTo()">
                @if (zmpl.chainRef("filter_assignment"))
                    <option></option>
                @else
                    <option selected></option>
                @end
                @if (zmpl.chainRef("filter_assignment") and !zmpl.chainRef("filter_has_assigned_to"))
                    <option selected>&lt;none&gt;</option>
                @else
                    <option>&lt;none&gt;</option>
                @end
                @zig {
                    const all_assignments = try zmpl.coerceArray("all_assignments");
                    const filter_assignment = zmpl.chainRef("filter_assignment");
                    const has_assigned_to = zmpl.chainRef("filter_has_assigned_to");
                    if (filter_assignment != null and filter_assignment.?.boolean.value) {
                        const filter_assigned_to = zmpl.chainRef("filter_assigned_to");
                        for (all_assignments) |assignment| {
                            @if (has_assigned_to and filter_assigned_to == assignment)
                                <option selected value="{{ assignment }}">{{ assignment }}</option>
                            @else
                                <option value="{{ assignment }}">{{ assignment }}</option>
                            @end
                        }
                    } else {
                        for (all_assignments) |assignment| {
                            <option value="{{ assignment }}">{{ assignment }}</option>
                        }
                    }
                }
            </select>
        </div>
    </div>
</div>
<table class="tasks_table">
    <thead>
        <tr>
            <th>
                Name
                @partial sort_button($.sort_field, $.sort_order, "name")
            </th>
            <th>
                Tags
            </th>
            <th>
                Priority
                @partial sort_button($.sort_field, $.sort_order, "priority")
            </th>
            <th>
                Assigned To
                @partial sort_button($.sort_field, $.sort_order, "assignment")
            </th>
            <th>
                Due By
            </th>
        </tr>
    </thead>
    <tbody>
        @for ($.tasks) |task| {
            <tr>
                <td>
                    <div class="task_header">
                        <a href="/show?id={{ task.id }}" class="task_header-name">{{ task.name }}</a>
                        <span class="task_header-num_notes">{{ task.num_notes }} Notes</span>
                    </div>
                </td>
                <td>
                    <div class="tags_list">
                        @zig {
                            const filter_tags2 = try zmpl.coerceArray("filter_tags");
                            if (task.chainRef("tags")) |tags| {
                                for (tags.array.items()) |tag| {
                                    const has_tag = for (filter_tags2) |filter_tag| {
                                        if (filter_tag.eql(tag.*)) break true;
                                    } else false;
                                    <div class="tag">
                                        <a href="#" onclick="onlyTag('{{ tag }}')">{{ tag }}</a>
                                        <div class="tag-quick_actions">
                                            @if (has_tag)
                                                <a href="#" onclick="removeTag('{{ tag }}')">[rem]</a>
                                            @else
                                                <a href="#" onclick="addTag('{{ tag }}')">[add]</a>
                                            @end
                                        </div>
                                    </div>
                                }
                            }
                        }
                    </div>
                </td>
                @if (task.chainRef("priority") == "critical")
                    <td class="priority_critical">
                        <span>{{ task.priority }}</span>
                    </td>
                @else if (task.chainRef("priority") == "high")
                    <td class="priority_high">
                        <span>{{ task.priority }}</span>
                    </td>
                @else if (task.chainRef("priority") == "medium")
                    <td class="priority_medium">
                        <span>{{ task.priority }}</span>
                    </td>
                @else if (task.chainRef("priority") == "low")
                    <td class="priority_low">
                        <span>{{ task.priority }}</span>
                    </td>
                @else
                    <td class="priority_none">
                        <span>{{ task.priority }}</span>
                    </td>
                @end
                <td><a href="#" onclick="setAssigned('{{ task.assigned_to }}')">{{ task.assigned_to }}</a></td>
                <td>{{ task.due_by }}</td>
            </tr>
        }
    </tbody>
</table>

<script>
    function setQuery(query) {
        const searchParams = new URLSearchParams(location.search);
        searchParams.set("filter_query", query);
        location.href = location.pathname + "?" + searchParams.toString();
    }

    function onlyTag(tagName) {
        const searchParams = new URLSearchParams(location.search);
        searchParams.set("filter_tags", tagName);
        location.href = location.pathname + "?" + searchParams.toString();
    }
    
    function addTag(tagName) {
        const searchParams = new URLSearchParams(location.search);
        let existingFilterTags = searchParams.get("filter_tags");
        if (!existingFilterTags) {
            onlyTag(tagName);
        } else {
            const tags = existingFilterTags.split(",");
            if (tags.indexOf(tagName) == -1) {
                tags.push(tagName);
            }
            searchParams.set("filter_tags", tags.join(","));
            location.href = location.pathname + "?" + searchParams.toString();
        }
    }
    
    function removeTag(tagName) {
        const searchParams = new URLSearchParams(location.search);
        let existingFilterTags = searchParams.get("filter_tags");
        if (existingFilterTags) {
            const tags = existingFilterTags.split(",");
            const idx = tags.indexOf(tagName);
            if (idx !== -1) {
                tags.splice(idx, 1);
            }
            searchParams.set("filter_tags", tags.join(","));
        }
        location.href = location.pathname + "?" + searchParams.toString();
    }

    function setNoAssignmentFilter() {
        const searchParams = new URLSearchParams(location.search);
        searchParams.delete("filter_assignment");
        searchParams.delete("filter_assigned_to");
        location.href = location.pathname + "?" + searchParams.toString();
    }

    function setUnassigned() {
        const searchParams = new URLSearchParams(location.search);
        searchParams.set("filter_assignment", "");
        searchParams.delete("filter_assigned_to");
        location.href = location.pathname + "?" + searchParams.toString();
    }

    function setAssigned(assignedTo) {
        const searchParams = new URLSearchParams(location.search);
        searchParams.set("filter_assignment", "");
        searchParams.set("filter_assigned_to", assignedTo);
        location.href = location.pathname + "?" + searchParams.toString();
    }

    function onSearchKeyPress(e) {
        console.log(e);
        if (e.key === "Enter") {
            updateSearchQuery();
        }
    }

    function updateSearchQuery() {
        const inputBox = document.getElementById("filter-query");
        if (!inputBox) return;

        setQuery(inputBox.value);
    }

    function addSelectedTag() {
        const selectBox = document.getElementById("filter-add_tag");
        if (!selectBox) return;

        addTag(selectBox.value);
    }

    function setSelectedAssignedTo() {
        const selectBox = document.getElementById("filter-assigned_to");
        if (!selectBox) return;

        if (selectBox.selectedIndex === 0) {
            setNoAssignmentFilter();
        } else if (selectBox.selectedIndex === 1) {
            setUnassigned();
        } else {
            setAssigned(selectBox.value);
        }
    }

    function sortByField(field, order) {
        const searchParams = new URLSearchParams(location.search);
        searchParams.set("sort_field", field);
        searchParams.set("sort_order", order);
        location.href = location.pathname + "?" + searchParams.toString();
    }
</script>