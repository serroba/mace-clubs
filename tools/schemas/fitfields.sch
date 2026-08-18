<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron">
    <title>Mace &amp; Clubs FIT presentation contract</title>
    <pattern id="fit-field-contract">
        <rule context="fitField">
            <assert test="not(@id = preceding::fitField/@id)">FIT field ids must be unique.</assert>
            <assert test="count(@displayInChart[. = 'true'] | @displayInActivityLaps[. = 'true'] | @displayInActivitySummary[. = 'true']) = 1">Each FIT field must have exactly one display target.</assert>
            <assert test="not(@displayInChart = 'true') or not(@sortOrder = preceding::fitField[@displayInChart = 'true']/@sortOrder)">Chart sortOrder values must be unique.</assert>
            <assert test="not(@displayInActivityLaps = 'true') or not(@sortOrder = preceding::fitField[@displayInActivityLaps = 'true']/@sortOrder)">Lap sortOrder values must be unique.</assert>
            <assert test="not(@displayInActivitySummary = 'true') or not(@sortOrder = preceding::fitField[@displayInActivitySummary = 'true']/@sortOrder)">Summary sortOrder values must be unique.</assert>
            <assert test="not(@displayInChart = 'true') or string-length(@chartTitle) &gt; 0">Chart fields require a chartTitle.</assert>
            <assert test="not(@displayInChart = 'true') or @unitLabel = '@Strings.FitPeakUnit' or @unitLabel = '@Strings.FitSwingsUnit' or @unitLabel = '@Strings.FitCadenceUnit'">Charts must display an approved recorded unit.</assert>
            <assert test="starts-with(@dataLabel, '@Strings.')">dataLabel must use a localized string.</assert>
            <assert test="starts-with(@unitLabel, '@Strings.')">unitLabel must use a localized string.</assert>
            <assert test="not(@chartTitle) or starts-with(@chartTitle, '@Strings.')">chartTitle must use a localized string.</assert>
        </rule>
    </pattern>
</schema>
