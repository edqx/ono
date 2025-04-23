<!DOCTYPE html>
<head>
    <html>
        <link rel="stylesheet" href="/resources/base_styles.css"/>
    </html>
    <body>
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
                        <td>{{ task.name }}</td>
                        <td>
                            @zig {
                                if (task.chainRef("tags")) |tags| {
                                    for (tags.array.items()) |tag| {
                                        <a href="#">{{ tag }}</a>
                                    }
                                }
                            }
                        </td>
                        <td>{{ task.priority }}</td>
                        <td>{{ task.assigned_to }}</td>
                        <td>{{ task.due_by }}</td>
                    </tr>
                }
            </tbody>
        </table>
    </body>
</head>