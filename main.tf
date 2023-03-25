resource "aws_vpc" "main" {
cidr_block = var.vpc_cidr
tags = merge(
var.tags,
{ Name = "${var.env}-vpc" }
)
}

## Public Subnets
resource "aws_subnet" "public_subnets" {
vpc_id = aws_vpc.main.id

for_each          = var.public_subnets
cidr_block        = each.value["cidr_block"]
availability_zone = each.value["availability_zone"]
tags = merge(
var.tags,
{ Name = "${var.env}-${each.value["name"]}" }
)
}

## Internet Gateway
resource "aws_internet_gateway" "igw" {
vpc_id = aws_vpc.main.id

tags = merge(
var.tags,
{ Name = "${var.env}-igw" }
)
}

# elastic Ip
resource "aws_eip" "nat" {
for_each = var.public_subnets
vpc      = true
}
#nat gateway
resource "aws_nat_gateway" "nat-gateways" {
for_each      = var.public_subnets
allocation_id = aws_eip.nat[each.value["name"]].id
subnet_id     = aws_subnet.public_subnets[each.value["name"]].id

tags = merge(
var.tags,
{ Name = "${var.env}-${each.value["name"]}" }
)
}

## Peering connection
resource "aws_vpc_peering_connection" "peer" {
  peer_owner_id = data.aws_caller_identity.account.id
  peer_vpc_id   = aws_vpc.main.id
  auto_accept   = true

  tags = merge(
    var.tags,
    { Name = "${var.env}-peer"}
  )
}

# Public Route table
resource "aws_route_table" "public-route-table" {
vpc_id = aws_vpc.main.id

route {
cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.igw.id
}
# add peer to route
  route {
    cidr_block = data.aws_vpc.default_vpc.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }
for_each = var.public_subnets
tags = merge(
var.tags,
{ Name = "${var.env}-${each.value["name"]}" }
)
}
# Public Route table association
resource "aws_route_table_association" "public-association" {
for_each  = var.public_subnets
subnet_id = lookup(lookup(aws_subnet.public_subnets, each.value["name"], null), "id", null)
route_table_id = aws_route_table.public-route-table[each.value["name"]].id
}

## Private Subnets
resource "aws_subnet" "private_subnets" {
vpc_id = aws_vpc.main.id

for_each          = var.private_subnets
cidr_block        = each.value["cidr_block"]
availability_zone = each.value["availability_zone"]
tags = merge(
var.tags,
{ Name = "${var.env}-${each.value["name"]}" }
)

}

# Private Route table
resource "aws_route_table" "private-route-table" {
vpc_id = aws_vpc.main.id

for_each = var.private_subnets
route {
  cidr_block     = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat-gateways["public-${split("-", each.value["name"])[1]}"].id
}
  # add peer to route
route {
  cidr_block = data.aws_vpc.default_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}
tags = merge(
var.tags,
{ Name = "${var.env}-${each.value["name"]}" }
)
}
# Private Route table association

resource "aws_route_table_association" "private-association" {
for_each       = var.private_subnets
subnet_id      = lookup(lookup(aws_subnet.private_subnets, each.value["name"], null), "id", null)
route_table_id = aws_route_table.private-route-table[each.value["name"]].id
}

## Route to the default vpc for peer to work

resource "aws_route" "route" {
  route_table_id = var.default_route_table
  destination_cidr_block = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}