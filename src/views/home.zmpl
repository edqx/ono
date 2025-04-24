<table class="tasks_table">
    <thead>
        <tr>
            <th>
                Name
            </th>
            <th>
                Tags
            </th>
            <th>
                Priority
            </th>
            <th>
                Assigned To
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
                    <div class="tags-list">
                        @zig {
                            const filter_tags = try zmpl.coerceArray("filter_tags");
                            if (task.chainRef("tags")) |tags| {
                                for (tags.array.items()) |tag| {
                                    const has_tag = for (filter_tags) |filter_tag| {
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

    function setAssigned(assignedTo) {
        const searchParams = new URLSearchParams(location.search);
        searchParams.set("filter_assignment", "");
        searchParams.set("assigned_to", assignedTo);
        location.href = location.pathname + "?" + searchParams.toString();
    }
</script>