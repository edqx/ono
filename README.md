# Ono
Ono is a ridiculously simple bug tracking system, issue tracking system, and project
management tool. Use files to create tasks, folders to organise them, and your favourite
source version manager to sync them with your team.

Since Ono tasks are just files on your filesystem, you can embed them in projects
seamlessly, and easily integrate them with any system.

## Tasks
To create a new task, create a `.ono` file in your project folder. The `.ono` file
is written in TOML, and has various properties to define what kind of task it is,
and helpful descriptors to find and manage them later through the CLI or web view.

Below is an example Ono task:
```toml
# write_shopping_list.ono
name="Write Shopping List"
tags=["shopping","personal","weekly"]

assigned_to="everyone"
priority="low"
status="unresolved"

[[notes]]
attributed_to="jen"
note="""
We're going shopping for the week tomorrow, remember to write down what you need to buy.
"""

[[notes]]
attributed_to="rhea"
note="""
We need to eat healthier!
"""
attachments=["images/food_pyramid.png"]

[[notes]]
attributed_to="phoebe"
note="""
I'm allergic to seafood. Let's not buy any of that.
"""
```

Check out the [Full Syntax](#full-syntax) section to know how to write any Ono task.

## CLI
Ono comes with a simple command line interface to view and manage your tasks. Use
`ono -h` to know how to use the command.

## Web Server
Ono also comes with a web server that can be used for a read-only view of the tasks.
If you want a full project management dashboard that integrates with Ono, I'm working
on another project, [Second](https://github.com/edqx/second).

## More Information
### What is 'ono'?
https://youtu.be/X6NJkWbM1xk