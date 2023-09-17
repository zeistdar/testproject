import pandas as pd

# Read the Excel file
file_name = 'data.xlsx'  # Replace with your Excel file name

# Load the Excel file into an ExcelFile object
xls = pd.ExcelFile(file_name, engine='openpyxl')

# Get the sheet names
sheet_names = xls.sheet_names

# Create an empty list to store dataframes after adding the 'source type' column
dfs = []

# Loop through the sheet names, read each sheet, and add the 'source type' column
for sheet_name in sheet_names:
    df = pd.read_excel(xls, sheet_name=sheet_name)
    df['source type'] = sheet_name
    dfs.append(df)

# Concatenate all the dataframes by rows
result = pd.concat(dfs, axis=0)

# Write the result to a CSV file
result.to_csv('output.csv', index=False)
