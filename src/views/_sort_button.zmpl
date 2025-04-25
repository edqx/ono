@args sort_field: []const u8, sort_order: []const u8, field: []const u8

@if (sort_field == field)
    @if (sort_order == "ascending")
        <a class="bare_link" href="#" onclick="sortByField('{{ field }}', 'descending')">&uarr;</a>
    @else if (sort_order == "descending")
        <a class="bare_link" href="#" onclick="sortByField('{{ field }}', 'ascending')">&darr;</a>
    @else
        <a class="bare_link" href="#" onclick="sortByField('{{ field }}', 'ascending')">&mdash;</a>
    @end
@else
    <a class="bare_link" href="#" onclick="sortByField('{{ field }}', 'ascending')">&mdash;</a>
@end