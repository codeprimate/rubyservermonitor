<?xml version='1.0'?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="/">
  <html>
	  <head>
		  <meta http-equiv="Refresh" content="300"/>
	  </head>
  <body>

  <style type="text/css">

	body {
		font-size: 90%;
	}

	table {
		border: 3px solid black;
		cell-padding: 5;
	}

	th {
		border: 1px solid black;
		background: lightgrey;
	}

	td {
		padding: 0.1em;
		padding-left: 0.5em;
		padding-right: 0.5em;
		margin: none;
		border: 0;
	}

	.servername {
		border: none;
		border-top: 2px solid black;
		background: #aaa;
	}

	.success {
		background: lightgreen;
	}

	.failure {
		background: red; 
	}

  </style>

  <h2>Monitoring Runs</h2>
  <xsl:for-each select="ServerMonitor/test_run">
	  <xsl:sort order="descending" select="date"/>
	<table cellspacing="0">
		<tr>
			<th colspan="5"><font size="+2"><xsl:value-of select="date"/></font></th>
		</tr>
		<tr>
			<th>Name</th>
			<th>Domain</th>
			<th>Port / URL</th>
			<th>Result</th>
			<th>Time</th>
		</tr>
		<xsl:for-each select="server">
			<xsl:sort select="name"/>
			<tr>
			<xsl:choose>
			 <xsl:when test="result = 'PASSED'">
				<td class="servername success"><b><xsl:value-of select="name"/></b></td>
			 </xsl:when>
			 <xsl:otherwise>
				 <td class="servername failure"><b><xsl:value-of select="name"/></b></td>
			 </xsl:otherwise>
			</xsl:choose>
				<td class="servername"><b><xsl:value-of select="domain"/></b></td>
				<td class="servername"></td>
				<xsl:choose>
					<xsl:when test="result = 'PASSED'">
						<td class="servername success" colspan="2"><xsl:value-of select="result"/></td>
					</xsl:when>
					<xsl:otherwise>
						<td class="servername failure" colspan="2"><xsl:value-of select="result"/></td>
					</xsl:otherwise>
				</xsl:choose>
			</tr>
			<xsl:for-each select="url">
				<xsl:sort select="url"/>
				<tr>
					<td colspan="2"></td>
					<td class="url"><xsl:value-of select="url"/></td>
					<xsl:choose>
						<xsl:when test="result = 'PASSED'">
							<td class="success"><xsl:value-of select="result"/></td>
						</xsl:when>
						<xsl:otherwise>
							<td class="failure"><xsl:value-of select="result"/></td>
						</xsl:otherwise>
					</xsl:choose>
					<td><xsl:value-of select="time"/></td>
				</tr>
			</xsl:for-each>
			<xsl:for-each select="port">
				<xsl:sort data-type="number" select="number"/>	
				<tr>
					<td colspan="2"></td>
					<td><xsl:value-of select="number"/></td>
					<xsl:choose>
						<xsl:when test="result = 'PASSED'">
							<td class="success"><xsl:value-of select="result"/></td>
						</xsl:when>
						<xsl:otherwise>
							<td class="failure"><xsl:value-of select="result"/></td>
						</xsl:otherwise>
					</xsl:choose>
					<td><xsl:value-of select="time"/></td>
				</tr>
			</xsl:for-each>
		</xsl:for-each>
	</table>
	<br/><br/><br/>
	</xsl:for-each>
  </body>
  </html>
</xsl:template>
</xsl:stylesheet>
